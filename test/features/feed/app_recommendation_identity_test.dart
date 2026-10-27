import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/feed/data/app_recommendation_identity_store.dart';
import 'package:bilisail/features/feed/data/api_feed_repository.dart';
import 'package:bilisail/features/feed/domain/app_recommendation_identity_repository.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/video/domain/video_actions_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late _Credentials credentials;
  late _Transport transport;
  late ApiRequests requests;
  late StreamController<AuthState> accounts;
  late AppRecommendationIdentityStore store;
  late String scope;
  late DateTime now;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    credentials = _Credentials();
    transport = _Transport();
    requests = ApiRequests();
    accounts = StreamController.broadcast(sync: true);
    scope = 'user:42';
    now = DateTime.utc(2026, 10, 27);
    store = AppRecommendationIdentityStore(
      api: BiliApiClient(transport: transport, sessionProvider: requests),
      requests: requests,
      database: database,
      credentials: credentials,
      accountScope: () => scope,
      accountChanges: accounts.stream,
      clock: () => now,
    );
  });
  tearDown(() async {
    await store.close();
    await accounts.close();
    await database.close();
  });
  Future<AppRecommendationAuthorization> begin() =>
      store.beginAuthorization(cancellation: RequestCancellation());
  Future<void> authorize() async {
    final attempt = await begin();
    expect(
      await store.pollAuthorization(
        attempt,
        cancellation: RequestCancellation(),
      ),
      AppRecommendationAuthorizationStatus.confirmed,
    );
  }

  test('device initialization is single flight, persistent, and has no network calls', () async {
    final identities = await Future.wait(List.generate(5, (_) => store.load()));
    expect(identities.map((value) => value.buvid).toSet(), hasLength(1));
    expect(identities.first.buvid, matches(r'^XY[0-9A-F]{35}$'));
    expect(
      await database.readSetting('app-recommendation-device.v1'),
      identities.first.buvid,
    );
    expect(credentials.reads, 1);
    expect(transport.calls, 0);
  });
  test('authorization persists only to secure storage and restores for the matching Web account', () async {
    await authorize();
    expect((await store.requestIdentity()).accessToken, 'fixture-access');
    expect((await store.load()).authorizedMid, '42');
    expect(jsonDecode(credentials.value!)['mid'], '42');
    final rows = await database
        .customSelect('SELECT value FROM settings')
        .get();
    expect(
      rows.any((row) => row.read<String>('value').contains('fixture-access')),
      isFalse,
    );
    scope = 'user:7';
    expect((await store.requestIdentity()).accessToken, isNull);
  });
  test(
    'a different scanned account is rejected before any credential write',
    () async {
      transport.mid = 7;
      final attempt = await begin();
      await expectLater(
        store.pollAuthorization(attempt, cancellation: RequestCancellation()),
        throwsA(
          isA<AppFailure>().having(
            (value) => value.kind,
            'kind',
            AppFailureKind.authentication,
          ),
        ),
      );
      expect(credentials.value, isNull);
      expect((await store.load()).authorizedMid, isNull);
    },
  );
  test(
    'cancelled and superseded QR attempts cannot commit a late response',
    () async {
      final attempt = await begin();
      transport.gate = Completer<void>();
      final cancellation = RequestCancellation();
      final result = store.pollAuthorization(
        attempt,
        cancellation: cancellation,
      );
      final assertion = expectLater(
        result,
        throwsA(
          isA<AppFailure>().having(
            (value) => value.kind,
            'kind',
            AppFailureKind.cancelled,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();
      transport.gate!.complete();
      await assertion;
      expect(credentials.value, isNull);
      transport.gate = null;
      await begin();
      await expectLater(
        store.pollAuthorization(attempt, cancellation: RequestCancellation()),
        throwsA(isA<AppFailure>()),
      );
    },
  );
  test('logout during secure persistence clears the late token and leaves a revocation marker', () async {
    final attempt = await begin();
    credentials.writeGate = Completer<void>();
    final result = store.pollAuthorization(
      attempt,
      cancellation: RequestCancellation(),
    );
    final assertion = expectLater(result, throwsA(isA<AppFailure>()));
    await credentials.writeStarted.future;
    scope = 'guest';
    requests.advanceSession();
    accounts.add(const AuthState());
    credentials.writeGate!.complete();
    await assertion;
    await store.clearAuthorization();
    expect(credentials.value, isNull);
    expect(
      await database.readSetting('app-recommendation-authorization-revoked.v1'),
      'true',
    );
    expect((await store.requestIdentity()).accessToken, isNull);
  });
  test(
    'failed secure write cannot commit a token or fall back to plain storage',
    () async {
      credentials.failWrite = true;
      final attempt = await begin();
      await expectLater(
        store.pollAuthorization(attempt, cancellation: RequestCancellation()),
        throwsStateError,
      );
      expect(credentials.value, isNull);
      expect((await store.load()).authorizedMid, isNull);
      expect(
        await database.readSetting(
          'app-recommendation-authorization-revoked.v1',
        ),
        'true',
      );
    },
  );
  test('device changes invalidate pending QR and authorization, preserving Web scope', () async {
    await authorize();
    final revision = store.revision;
    final attempt = await begin();
    await store.setBuvid('device_0123456789abcdef');
    expect(store.revision, greaterThan(revision));
    expect((await store.requestIdentity()).accessToken, isNull);
    expect((await store.load()).buvid, 'device_0123456789abcdef');
    expect(scope, 'user:42');
    expect(credentials.value, isNull);
    await expectLater(
      store.pollAuthorization(attempt, cancellation: RequestCancellation()),
      throwsA(isA<AppFailure>()),
    );
    await expectLater(store.setBuvid('bad'), throwsArgumentError);
  });
  test('expired or invalidated authorization fails explicitly instead of sending guest requests', () async {
    await authorize();
    now = now.add(const Duration(days: 2));
    expect((await store.load()).expired, isTrue);
    await expectLater(
      store.requestIdentity(),
      throwsA(
        isA<AppFailure>().having(
          (value) => value.kind,
          'kind',
          AppFailureKind.authentication,
        ),
      ),
    );
    now = now.subtract(const Duration(days: 2));
    await store.invalidateAuthorization();
    expect(jsonDecode(credentials.value!)['invalid'], isTrue);
    await expectLater(store.requestIdentity(), throwsA(isA<AppFailure>()));
    await store.clearAuthorization();
    expect((await store.requestIdentity()).accessToken, isNull);
  });
  test('expired QR has a bounded terminal result without polling', () async {
    final attempt = await begin();
    final calls = transport.calls;
    now = now.add(const Duration(minutes: 3));
    expect(
      await store.pollAuthorization(
        attempt,
        cancellation: RequestCancellation(),
      ),
      AppRecommendationAuthorizationStatus.expired,
    );
    expect(transport.calls, calls);
  });
  test('revocation marker blocks restoring an orphan secure slot after deletion fails', () async {
    await authorize();
    credentials.failDelete = true;
    await expectLater(store.clearAuthorization(), throwsStateError);
    expect(
      await database.readSetting('app-recommendation-authorization-revoked.v1'),
      'true',
    );
    await expectLater(store.requestIdentity(), throwsA(isA<AppFailure>()));
    credentials.failDelete = false;
    await store.clearAuthorization();
    expect((await store.requestIdentity()).accessToken, isNull);
  });
  test('restart restores matching secure authorization but discards another account', () async {
    await authorize();
    await store.close();
    store = AppRecommendationIdentityStore(
      api: BiliApiClient(transport: transport, sessionProvider: requests),
      requests: requests,
      database: database,
      credentials: credentials,
      accountScope: () => scope,
      accountChanges: accounts.stream,
      clock: () => now,
    );
    accounts.add(const AuthState(status: AuthStatus.signedIn, mid: '42'));
    expect((await store.requestIdentity()).accessToken, 'fixture-access');
    await store.close();
    scope = 'user:7';
    store = AppRecommendationIdentityStore(
      api: BiliApiClient(transport: transport, sessionProvider: requests),
      requests: requests,
      database: database,
      credentials: credentials,
      accountScope: () => scope,
      accountChanges: accounts.stream,
      clock: () => now,
    );
    expect((await store.requestIdentity()).accessToken, isNull);
    expect(credentials.value, isNull);
  });
  RecommendationFeedback feedback() => RecommendationFeedback.app(
    aid: '170001',
    ownerMid: '42',
    identityRevision: store.revision,
    reasons: const [
      RecommendationFeedbackReason(
        id: '7',
        name: 'fixture reason',
        kind: RecommendationFeedbackReasonKind.feedback,
      ),
    ],
  );
  ApiFeedRepository repository() => ApiFeedRepository(
    BiliApiClient(transport: transport, sessionProvider: requests),
    requests,
    appIdentity: store,
  );
  test(
    'App feedback requires explicit App authorization even with a Web account',
    () async {
      final value = feedback();
      await expectLater(
        repository().rejectRecommendation(
          value.selectReason(value.reasons.single),
          cancellation: RequestCancellation(),
        ),
        throwsA(
          isA<AppFailure>().having(
            (value) => value.message,
            'message',
            contains('扫码授权'),
          ),
        ),
      );
      expect(transport.gets, isEmpty);
    },
  );
  test('App feedback keeps the selected server reason and uses its matching undo endpoint', () async {
    await authorize();
    final value = feedback();
    final selected = value.selectReason(value.reasons.single);
    await repository().rejectRecommendation(
      selected,
      cancellation: RequestCancellation(),
    );
    expect(transport.gets.single.queryParameters['feedback_id'], '7');
    expect(
      transport.gets.single.queryParameters['access_key'],
      'fixture-access',
    );
    await repository().undoRecommendationFeedback(
      selected,
      cancellation: RequestCancellation(),
    );
    expect(transport.gets.last.path, '/x/feed/dislike/cancel');
    await store.setBuvid('new_device_0123456789');
    await expectLater(
      repository().rejectRecommendation(
        selected,
        cancellation: RequestCancellation(),
      ),
      throwsA(
        isA<AppFailure>().having(
          (value) => value.kind,
          'kind',
          AppFailureKind.cancelled,
        ),
      ),
    );
    expect(transport.gets, hasLength(2));
  });
  test('uncertain App feedback remains single attempt across the repository boundary', () async {
    await authorize();
    transport.getStatus = 503;
    final value = feedback();
    await expectLater(
      repository().rejectRecommendation(
        value.selectReason(value.reasons.single),
        cancellation: RequestCancellation(),
      ),
      throwsA(isA<UnknownWriteOutcome>()),
    );
    expect(transport.gets, hasLength(1));
  });
}

final class _Credentials implements CredentialStore {
  String? value;
  int reads = 0;
  bool failWrite = false, failDelete = false;
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();
  @override
  Future<String?> read() async {
    reads++;
    return value;
  }

  @override
  Future<void> write(String data) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    if (failWrite) throw StateError('secure write failed');
    value = data;
  }

  @override
  Future<void> delete() async {
    if (failDelete) throw StateError('secure delete failed');
    value = null;
  }
}

final class _Transport implements ApiTransport, ApiFormTransport {
  int mid = 42, calls = 0;
  int getStatus = 200;
  final gets = <Uri>[];
  Completer<void>? gate;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    gets.add(uri);
    return ApiHttpResponse(
      getStatus,
      Uint8List.fromList(utf8.encode('{"code":0,"data":{}}')),
      const {},
    );
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    calls++;
    final poll = uri.path.endsWith('/poll');
    if (poll) await gate?.future;
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'code': 0,
            'data': poll
                ? {
                    'token_info': {
                      'mid': mid,
                      'access_token': 'fixture-access',
                      'expires_in': 86400,
                    },
                  }
                : {
                    'auth_code': 'fixture-code',
                    'url': 'https://passport.bilibili.com/fixture',
                  },
          }),
        ),
      ),
      const {},
    );
  }
}
