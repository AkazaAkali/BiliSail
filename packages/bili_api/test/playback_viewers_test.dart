import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'online viewers preserve server total and exact content identity',
    () async {
      final transport = _Transport({'total': '1.2万+', 'count': '100'});
      final client = PlaybackMetadataClient(
        BiliApiClient(transport: transport),
      );
      expect(
        await client.onlineViewers('BV1abc123456', '9007199254740995'),
        '1.2万+',
      );
      final uri = transport.uris.single;
      expect(uri.host, 'api.bilibili.com');
      expect(uri.path, '/x/player/online/total');
      expect(uri.queryParameters, {
        'bvid': 'BV1abc123456',
        'cid': '9007199254740995',
      });
    },
  );

  test(
    'visibility and unavailable totals do not fabricate zero viewers',
    () async {
      for (final data in <Map<String, Object?>>[
        {},
        {'total': ''},
        {
          'total': '92',
          'show_switch': {'total': false},
        },
      ]) {
        final client = PlaybackMetadataClient(
          BiliApiClient(transport: _Transport(data)),
        );
        expect(await client.onlineViewers('BV1abc123456', '123'), isNull);
      }
      final client = PlaybackMetadataClient(
        BiliApiClient(transport: _Transport({'total': 0})),
      );
      expect(await client.onlineViewers('BV1abc123456', '123'), '0');
    },
  );

  test('malformed counts are protocol failures', () async {
    for (final value in <Object>[-1, 1.5, {}, 'not a count', '9' * 25]) {
      final client = PlaybackMetadataClient(
        BiliApiClient(transport: _Transport({'total': value})),
      );
      await expectLater(
        client.onlineViewers('BV1abc123456', '123'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    }
  });

  test(
    'invalid identity and cancelled requests never reach transport',
    () async {
      final transport = _Transport({'total': '92'});
      final client = PlaybackMetadataClient(
        BiliApiClient(transport: transport),
      );
      await expectLater(
        client.onlineViewers('bad', '123'),
        throwsArgumentError,
      );
      await expectLater(
        client.onlineViewers('BV1abc123456', 'bad'),
        throwsArgumentError,
      );
      final cancellation = ApiCancellation()..cancel();
      await expectLater(
        client.onlineViewers(
          'BV1abc123456',
          '123',
          context: ApiRequestContext(cancellation: cancellation),
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.cancelled,
          ),
        ),
      );
      expect(transport.uris, isEmpty);
    },
  );
}

class _Transport implements ApiTransport {
  _Transport(this.data);
  final Map<String, Object?> data;
  final uris = <Uri>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    uris.add(uri);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
