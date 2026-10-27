import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/credential_store.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/app_recommendation_identity_repository.dart';

final class AppRecommendationIdentityStore
    implements AppRecommendationIdentityRepository {
  AppRecommendationIdentityStore({
    required this.api,
    required this.requests,
    required this.database,
    required this.credentials,
    required this.accountScope,
    required Stream<AuthState> accountChanges,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _accountSubscription = accountChanges.listen((value) {
      if (value.status == AuthStatus.signedIn ||
          value.status == AuthStatus.guest) {
        final scope = value.status == AuthStatus.guest
            ? 'guest'
            : 'user:${value.mid}';
        final changed = _observedScope != null && _observedScope != scope;
        _observedScope = scope;
        _version++;
        _pending = null;
        // Identity is isolated synchronously, before queued secure deletion.
        if (value.status == AuthStatus.guest ||
            changed ||
            _stored != null && _stored?.mid != value.mid) {
          _stored = null;
          _discarded = true;
          unawaited(
            _enqueue(_deleteCredentials).catchError((Object error) {
              _storageFailure = true;
              _emit();
            }),
          );
        }
        _emit();
      }
    });
  }
  final BiliApiClient api;
  final ApiRequests requests;
  final AppDatabase database;
  final CredentialStore credentials;
  final String Function() accountScope;
  final DateTime Function() _clock;
  late final StreamSubscription<AuthState> _accountSubscription;
  final _changes = StreamController<int>.broadcast();
  Future<void> _writes = Future.value();
  Future<void>? _loaded;
  String _buvid = '';
  ApiAppCredentials? _stored;
  bool _discarded = false, _invalid = false, _closed = false;
  int _version = 0;
  String? _observedScope;
  bool _storageFailure = false;
  int _authorizationSequence = 0;
  (AppRecommendationAuthorization, String, int)? _pending;

  @override
  int get revision => _version;
  @override
  Stream<int> get changes => _changes.stream;
  void _emit() {
    if (!_closed) _changes.add(_version);
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _ensureLoaded() =>
      _loaded ??= _read().catchError((Object error, StackTrace stack) {
        _loaded = null;
        Error.throwWithStackTrace(error, stack);
      });
  Future<void> _read() async {
    final savedDevice = await database.readSetting(
      'app-recommendation-device.v1',
    );
    _buvid = savedDevice != null && _validBuvid(savedDevice)
        ? savedDevice
        : _generateBuvid();
    if (_buvid != savedDevice) {
      await database.writeSetting('app-recommendation-device.v1', _buvid);
    }
    final saved = await credentials.read();
    final revoked = await database.readSetting(
      'app-recommendation-authorization-revoked.v1',
    );
    if (saved == null || revoked == 'true' || _discarded || _closed) return;
    try {
      final Object? value = jsonDecode(saved);
      if (value is! Map<String, Object?> ||
          value['mid'] is! String ||
          value['accessToken'] is! String ||
          value['expiresAtMillis'] is! int ||
          !RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(value['mid'] as String)) {
        throw const FormatException('Invalid App credential snapshot');
      }
      final token = value['accessToken'] as String;
      final millis = value['expiresAtMillis'] as int;
      if (token.isEmpty ||
          token.length > 4096 ||
          millis < 0 ||
          millis > 8640000000000000) {
        throw const FormatException('Invalid App credential fields');
      }
      _stored = ApiAppCredentials(
        mid: value['mid'] as String,
        accessToken: token,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(millis),
      );
      _invalid = value['invalid'] == true;
      if (accountScope().startsWith('user:') &&
          accountScope() != 'user:${_stored?.mid}') {
        _stored = null;
        _discarded = true;
        await _enqueue(_deleteCredentials);
      }
    } on FormatException {
      throw const AppFailure(
        AppFailureKind.authentication,
        'App 推荐授权数据无效，请清除授权后重新扫码',
      );
    }
  }

  static bool _validBuvid(String value) =>
      AppRecommendationIdentity.validBuvid(value);
  static String _generateBuvid() {
    final random = Random.secure();
    final hex = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join().toUpperCase();
    return 'XY${hex[2]}${hex[12]}${hex[22]}$hex';
  }

  ApiAppCredentials? get _current =>
      accountScope() == 'user:${_stored?.mid}' ? _stored : null;
  @override
  Future<AppRecommendationIdentity> load() async {
    await _ensureLoaded();
    if (_storageFailure) {
      throw const AppFailure(AppFailureKind.protocol, 'App 推荐安全存储清理失败，请重试清除授权');
    }
    final current = _current;
    return AppRecommendationIdentity(
      buvid: _buvid,
      authorizedMid: current?.mid,
      canAuthorize: accountScope().startsWith('user:'),
      expiresAt: current?.expiresAt,
      expired:
          current != null && (_invalid || !current.expiresAt.isAfter(_clock())),
    );
  }

  Future<({String buvid, String? accessToken, int revision})>
  requestIdentity() async {
    await _ensureLoaded();
    if (_storageFailure) {
      throw const AppFailure(
        AppFailureKind.protocol,
        'App 推荐安全存储清理失败，请在设置中清除授权后重试',
      );
    }
    final current = _current;
    if (current != null && (_invalid || !current.expiresAt.isAfter(_clock()))) {
      throw const AppFailure(
        AppFailureKind.authentication,
        'App 推荐授权已过期，请在推荐流设置中重新扫码授权',
      );
    }
    return (
      buvid: _buvid,
      accessToken: current?.accessToken,
      revision: _version,
    );
  }

  @override
  Future<void> setBuvid(String value) async {
    if (!_validBuvid(value)) {
      throw ArgumentError('设备标识须为 16–128 位字母、数字、下划线或连字符');
    }
    await _ensureLoaded();
    if (value == _buvid) return;
    await _enqueue(() async {
      await database.writeSetting('app-recommendation-device.v1', value);
      _buvid = value;
      _stored = null;
      _discarded = true;
      _invalid = false;
      _pending = null;
      _version++;
      _emit();
      await _deleteCredentials();
    });
  }

  @override
  Future<void> randomizeBuvid() => setBuvid(_generateBuvid());
  @override
  Future<void> clearAuthorization() async {
    _stored = null;
    _discarded = true;
    _invalid = false;
    _pending = null;
    _version++;
    _emit();
    await _enqueue(_deleteCredentials);
  }

  Future<void> _deleteCredentials() async {
    try {
      try {
        await database.writeSetting(
          'app-recommendation-authorization-revoked.v1',
          'true',
        );
      } finally {
        await credentials.delete();
      }
      _storageFailure = false;
    } catch (_) {
      _storageFailure = true;
      rethrow;
    } finally {
      _emit();
    }
  }

  Future<void> invalidateAuthorization() async {
    final current = _current;
    if (current == null) return;
    _invalid = true;
    _version++;
    _emit();
    await _enqueue(() async {
      if (identical(_stored, current)) {
        await credentials.write(_serialize(current));
      }
    });
  }

  String _serialize(ApiAppCredentials value, {bool? invalid}) => jsonEncode({
    'schemaVersion': 1,
    'mid': value.mid,
    'accessToken': value.accessToken,
    'expiresAtMillis': value.expiresAt.millisecondsSinceEpoch,
    'invalid': invalid ?? _invalid,
  });

  @override
  Future<AppRecommendationAuthorization> beginAuthorization({
    required RequestCancellation cancellation,
  }) async {
    await _ensureLoaded();
    if (!accountScope().startsWith('user:')) {
      throw const AppFailure(
        AppFailureKind.authentication,
        '请先登录哔哩哔哩，再授权同一账号的 App 推荐',
      );
    }
    final version = _version;
    final sequence = ++_authorizationSequence;
    _pending = null;
    final result = await requests.run(
      (context) => AppPassportClient(
        api,
        clock: _clock,
      ).generate(buvid: _buvid, context: context),
      cancellation: cancellation,
    );
    if (sequence != _authorizationSequence ||
        version != _version ||
        cancellation.isCancelled ||
        _closed) {
      throw const AppFailure(AppFailureKind.cancelled, '授权已取消');
    }
    final attempt = AppRecommendationAuthorization(
      url: result.url,
      expiresAt: _clock().add(const Duration(minutes: 2)),
    );
    _pending = (attempt, result.authCode, version);
    return attempt;
  }

  @override
  Future<AppRecommendationAuthorizationStatus> pollAuthorization(
    AppRecommendationAuthorization attempt, {
    required RequestCancellation cancellation,
  }) async {
    final pending = _pending;
    if (identical(pending?.$1, attempt) &&
        !attempt.expiresAt.isAfter(_clock())) {
      _pending = null;
      return AppRecommendationAuthorizationStatus.expired;
    }
    bool valid() =>
        !_closed &&
        !cancellation.isCancelled &&
        attempt.expiresAt.isAfter(_clock()) &&
        identical(_pending?.$1, attempt) &&
        pending?.$3 == _version;
    if (!valid() || pending == null) {
      throw const AppFailure(AppFailureKind.cancelled, '授权已取消');
    }
    final result = await requests.run(
      (context) => AppPassportClient(
        api,
        clock: _clock,
      ).poll(buvid: _buvid, authCode: pending.$2, context: context),
      cancellation: cancellation,
    );
    if (!valid()) throw const AppFailure(AppFailureKind.cancelled, '授权已取消');
    if (result.status != ApiQrStatus.confirmed) {
      return switch (result.status) {
        ApiQrStatus.expired => AppRecommendationAuthorizationStatus.expired,
        ApiQrStatus.waitingConfirm =>
          AppRecommendationAuthorizationStatus.waitingConfirm,
        _ => AppRecommendationAuthorizationStatus.waitingScan,
      };
    }
    final token = result.credentials;
    if (token == null || accountScope() != 'user:${token.mid}') {
      _pending = null;
      throw const AppFailure(
        AppFailureKind.authentication,
        '扫码账号与当前登录账号不同，请使用同一账号重新授权',
      );
    }
    await _enqueue(() async {
      if (!valid()) throw const AppFailure(AppFailureKind.cancelled, '授权已取消');
      // A crash or failed commit must never restore an uncommitted token.
      await database.writeSetting(
        'app-recommendation-authorization-revoked.v1',
        'true',
      );
      try {
        await credentials.write(_serialize(token, invalid: false));
        if (!valid()) {
          throw const AppFailure(AppFailureKind.cancelled, '授权已取消');
        }
        await database.writeSetting(
          'app-recommendation-authorization-revoked.v1',
          'false',
        );
        if (!valid()) {
          throw const AppFailure(AppFailureKind.cancelled, '授权已取消');
        }
      } catch (_) {
        _stored = null;
        _discarded = true;
        _version++;
        _emit();
        await _deleteCredentials();
        rethrow;
      }
      _stored = token;
      _discarded = false;
      _invalid = false;
      _pending = null;
      _version++;
      _emit();
    });
    return AppRecommendationAuthorizationStatus.confirmed;
  }

  Future<void> close() async {
    _closed = true;
    _pending = null;
    await _accountSubscription.cancel();
    await _loaded?.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    await _writes;
    await _changes.close();
  }
}
