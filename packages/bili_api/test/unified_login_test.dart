import 'dart:convert';
import 'dart:typed_data';
import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _device = 'fixture_device_0123456789';
Map<String, Object?> _token() => {
  'mid': 42,
  'access_token': 'fixture-app',
  'refresh_token': 'fixture-refresh',
  'expires_in': 86400,
  'cookie_info': {
    'cookies': [
      {'name': 'SESSDATA', 'value': 'fixture'},
      {'name': 'bili_jct', 'value': 'fixture-csrf'},
    ],
  },
};
void main() {
  test(
    'Web exchange waits for pending reads without replaying confirm',
    () async {
      final transport = _Transport()..pendingPolls = 2;
      final api = BiliApiClient(transport: transport);
      api.cookieJar.receive(Uri.https('passport.bilibili.com', '/'), [
        'SESSDATA=fixture; Domain=.bilibili.com; Path=/; Secure',
        'bili_jct=fixture-csrf; Domain=.bilibili.com; Path=/; Secure',
      ]);
      final result = await AppPassportClient(api).exchangeWebSession(
        buvid: _device,
        context: ApiRequestContext(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
      expect(result.status, ApiQrStatus.confirmed);
      expect(
        transport.uris.where((uri) => uri.path.endsWith('/confirm')),
        hasLength(1),
      );
      expect(
        transport.uris.where((uri) => uri.path.endsWith('/poll')),
        hasLength(3),
      );
    },
  );
  test(
    'HD response uses top-level token and Cookie metadata in one result',
    () async {
      final transport = _Transport()..data = _token();
      final result = await AppPassportClient(
        BiliApiClient(transport: transport),
      ).poll(buvid: _device, authCode: 'fixture-code');
      expect(result.credentials?.accessToken, 'fixture-app');
      expect(result.credentials?.refreshToken, 'fixture-refresh');
      expect(result.cookies.map((cookie) => cookie.name), [
        'SESSDATA',
        'bili_jct',
      ]);
      expect(
        result.cookies.every((cookie) => cookie.domain == 'bilibili.com'),
        isTrue,
      );
      expect(transport.headers.single.containsKey('Cookie'), isFalse);
    },
  );
  for (final bad in [
    {'name': 'SESSDATA', 'value': 'fixture', 'domain': 'example.com'},
    {'name': 'SESSDATA', 'value': 'fixture\r\nCookie: bad'},
    {'name': 'bad;name', 'value': 'fixture'},
    {'name': 'SESSDATA', 'value': 'fixture', 'expires': -2},
  ]) {
    test('invalid returned Cookie cannot enter a session: $bad', () async {
      final transport = _Transport()
        ..data = {
          ..._token(),
          'cookie_info': {
            'cookies': [bad],
          },
        };
      await expectLater(
        AppPassportClient(
          BiliApiClient(transport: transport),
        ).poll(buvid: _device, authCode: 'fixture-code'),
        throwsA(
          isA<ApiFailure>().having(
            (value) => value.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    });
  }
  test(
    'confirm binds only the fixed passport host, Cookie and CSRF and is a single write',
    () async {
      final transport = _Transport()..status = 503;
      final api = BiliApiClient(transport: transport);
      api.cookieJar.receive(Uri.https('passport.bilibili.com', '/'), [
        'SESSDATA=fixture; Domain=.bilibili.com; Path=/; Secure',
        'bili_jct=fixture-csrf; Domain=.bilibili.com; Path=/; Secure',
      ]);
      await expectLater(
        api.confirmAppLogin('fixture-code'),
        throwsA(isA<ApiFailure>()),
      );
      expect(
        transport.uris.single,
        Uri.https(
          'passport.bilibili.com',
          '/x/passport-tv-login/h5/qrcode/confirm',
        ),
      );
      expect(transport.fields.single['csrf'], 'fixture-csrf');
      expect(transport.fields.single['auth_code'], 'fixture-code');
      expect(transport.headers.single['Cookie'], contains('SESSDATA=fixture'));
    },
  );
  test(
    'confirm requires an applicable Cookie and CSRF before sending anything',
    () async {
      final transport = _Transport();
      final api = BiliApiClient(transport: transport);
      api.cookieJar.receive(Uri.https('passport.bilibili.com', '/private'), [
        'SESSDATA=fixture; Path=/private; Secure',
        'bili_jct=fixture-csrf; Path=/private; Secure',
      ]);
      await expectLater(
        api.confirmAppLogin('fixture-code'),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.uris, isEmpty);
    },
  );
}

final class _Transport implements ApiTransport, ApiFormTransport {
  Object data = {};
  int status = 200;
  int? pendingPolls;
  final uris = <Uri>[];
  final fields = <Map<String, String>>[], headers = <Map<String, String>>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => throw StateError('unexpected GET');
  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    uris.add(uri);
    this.fields.add(fields);
    this.headers.add(headers);
    if (pendingPolls != null) {
      final poll = uri.path.endsWith('/poll');
      final pending = poll && pendingPolls! > 0;
      if (pending) pendingPolls = pendingPolls! - 1;
      final result = uri.path.endsWith('/auth_code')
          ? {
              'auth_code': 'fixture-code',
              'url': 'https://passport.bilibili.com/fixture',
            }
          : _token();
      return ApiHttpResponse(
        200,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'code': pending ? 86039 : 0,
              'data': pending ? null : result,
            }),
          ),
        ),
        const {},
      );
    }
    return ApiHttpResponse(
      status,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
