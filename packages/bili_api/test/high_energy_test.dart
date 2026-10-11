import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

Object _loader(List<Object?> values, {Object step = 1, String tags = ''}) => {
  'modules': [
    {
      'name': 'pbp',
      'script_src': 'https://untrusted.invalid/script.js',
      'params': {
        'data': {
          'events': {'default': values},
          'step_sec': step,
          'tagstr': tags,
        },
      },
    },
  ],
};

void main() {
  test(
    'fixed public loader preserves IDs and decimals without credentials',
    () async {
      final transport = _Transport(_loader([0, 2.5, 5, 1]));
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final result = await HighEnergyClient(
        api,
      ).load('9007199254740993', '9007199254740995', 'BV1VEHn6TEKq');
      expect(result?.points.map((p) => p.intensity), [0, .5, 1, .2]);
      expect(result?.span, const Duration(seconds: 4));
      expect(
        transport.uris.single.toString(),
        'https://bvc.bilivideo.com/pbp/data?aid=9007199254740993&cid=9007199254740995&bvid=BV1VEHn6TEKq&r=loader',
      );
      expect(transport.headers.single.keys, isNot(contains('Cookie')));
      expect(transport.headers.single.keys, isNot(contains('Authorization')));
      expect(
        transport.timeouts.single,
        lessThanOrEqualTo(const Duration(seconds: 6)),
      );
    },
  );

  test(
    'large curves retain extrema, endpoints and order within 512 points',
    () async {
      final values = List<Object?>.filled(20000, 2);
      values[12345] = 999.5;
      values[12346] = 0;
      final api = BiliApiClient(transport: _Transport(_loader(values)));
      addTearDown(api.close);
      final result = await HighEnergyClient(api).load('1', '2', 'BV1VEHn6TEKq');
      expect(result, isNotNull);
      expect(result!.points.length, lessThanOrEqualTo(512));
      expect(result.points.first.fraction, 0);
      expect(result.points.last.fraction, 1);
      expect(result.points.map((p) => p.intensity), containsAll([0, 1]));
      for (var i = 1; i < result.points.length; i++) {
        expect(
          result.points[i].fraction,
          greaterThan(result.points[i - 1].fraction),
        );
      }
    },
  );

  for (final payload in [
    _loader([0, 0]),
    _loader([]),
    _loader([1, 2], tags: 'x_0&pbphide_1'),
    {'modules': <Object?>[]},
  ]) {
    test('empty/hidden capability is a normal fallback: $payload', () async {
      final api = BiliApiClient(transport: _Transport(payload));
      addTearDown(api.close);
      expect(
        await HighEnergyClient(api).load('1', '2', 'BV1VEHn6TEKq'),
        isNull,
      );
    });
  }
  for (final payload in [
    _loader([-1, 2]),
    _loader(['1', 2]),
    _loader([1, 2], step: 0),
    _loader([1, 2], step: .0001),
    _loader([1, 2], step: 400000),
    _loader(List.filled(20001, 1)),
    {'code': 0, 'data': {}},
    {'modules': List.filled(17, {})},
  ]) {
    test('malformed or excessive payload is rejected without retry', () async {
      final transport = _Transport(payload);
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      await expectLater(
        HighEnergyClient(api).load('1', '2', 'BV1VEHn6TEKq'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
      expect(transport.uris, hasLength(1));
    });
  }
  for (final status in [403, 404, 429, 302, 503]) {
    test('HTTP $status uses the bounded retry policy', () async {
      final transport = _Transport({}, status: status);
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      await expectLater(
        api.highEnergyBytes('1', '2', 'BV1VEHn6TEKq'),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.uris.length, status == 503 ? 2 : 1);
    });
  }
  test('cancelled and expired calls never reach transport', () async {
    final transport = _Transport(_loader([1, 2]));
    final api = BiliApiClient(transport: transport);
    addTearDown(api.close);
    await expectLater(
      api.highEnergyBytes(
        '1',
        '2',
        'BV1VEHn6TEKq',
        context: ApiRequestContext(cancellation: ApiCancellation()..cancel()),
      ),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      api.highEnergyBytes(
        '1',
        '2',
        'BV1VEHn6TEKq',
        context: ApiRequestContext(
          deadline: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.uris, isEmpty);
  });
  test(
    'streaming cap applies to gzip decompressed bytes before buffering',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.headers.set('content-encoding', 'gzip');
        request.response.add(
          request.uri.path == '/bad'
              ? [1, 2, 3]
              : gzip.encode(List.filled(300000, 65)),
        );
        await request.response.close();
      });
      final transport = DioApiTransport();
      try {
        await expectLater(
          transport.getBounded(
            Uri.parse('http://127.0.0.1:${server.port}/'),
            headers: const {},
            timeout: const Duration(seconds: 3),
            maxBytes: 256 * 1024,
          ),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.category,
              'category',
              ApiFailureCategory.protocol,
            ),
          ),
        );
        await expectLater(
          transport.getBounded(
            Uri.parse('http://127.0.0.1:${server.port}/bad'),
            headers: const {},
            timeout: const Duration(seconds: 3),
            maxBytes: 256 * 1024,
          ),
          throwsA(isA<ApiFailure>()),
        );
      } finally {
        transport.close();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}

class _Transport implements ApiTransport {
  _Transport(this.payload, {this.status = 200});
  final Object payload;
  final int status;
  final uris = <Uri>[];
  final headers = <Map<String, String>>[];
  final timeouts = <Duration>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    uris.add(uri);
    this.headers.add(headers);
    timeouts.add(timeout);
    return ApiHttpResponse(
      status,
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      const {},
    );
  }
}
