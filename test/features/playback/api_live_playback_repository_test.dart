import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/media_cdn.dart';
import 'package:bilisail/features/playback/data/api_content_playback_repository.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final quality in [0, 400, 10000]) {
    test(
      'live resolution keeps stream-specific qualities and server line order: qn=$quality',
      () async {
        final transport = _Transport();
        final requests = ApiRequests();
        final api = BiliApiClient(
          transport: transport,
          sessionProvider: requests,
        );
        addTearDown(api.close);
        final repository = ApiContentPlaybackRepository(
          PgcClient(api),
          LiveClient(api),
          requests,
          cdnPreference: () async => MediaCdnPreference.tencent,
        );
        final media = await repository.resolve(
          const LivePlaybackTarget('8'),
          quality: quality,
          cancellation: RequestCancellation(),
        );
        expect(transport.request?.queryParameters['qn'], '$quality');
        expect(media.kind, PlaybackMediaKind.liveHls);
        expect(media.video.codec, 'avc');
        expect(media.quality, quality == 0 ? 250 : quality);
        // HEVC/FLV-only qualities must not appear in the selected AVC HLS menu.
        expect(media.qualities, [10000, 400, 250]);
        expect(media.qualityLabels[400], '1080P 蓝光');
        expect(media.video.urls.map((uri) => uri.host), [
          'primary.example',
          'backup.example',
        ]);
        expect(media.video.urls.last.queryParameters['sign'], 'backup');
        expect(media.headers['Referer'], 'https://live.bilibili.com/');
        expect(media.audio, isNull);
        expect(media.duration, Duration.zero);
      },
    );
  }
}

final class _Transport implements ApiTransport {
  Uri? request;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    request = uri;
    final requested = int.parse(uri.queryParameters['qn'] ?? '0');
    Map<String, Object?> codec(String name, List<int> qualities) => {
      'codec_name': name,
      'current_qn': requested == 0 ? 250 : requested,
      'accept_qn': qualities,
      'base_url': '/live.m3u8?',
      'url_info': [
        {'host': 'https://primary.example', 'extra': 'sign=primary'},
        {'host': 'https://backup.example', 'extra': 'sign=backup'},
      ],
    };
    final data = {
      'room_id': 8,
      'live_status': 1,
      'playurl_info': {
        'playurl': {
          'g_qn_desc': [
            {'qn': 250, 'desc': '超清'},
            {
              'qn': 400,
              'desc': '蓝光',
              'media_base_desc': {
                'detail_desc': {'desc': '1080P 蓝光'},
              },
            },
            {'qn': 10000, 'desc': '原画'},
            {'qn': 20000, 'desc': '4K'},
          ],
          'stream': [
            {
              'protocol_name': 'http_stream',
              'format': [
                {
                  'format_name': 'flv',
                  'codec': [
                    codec('avc', [20000, 10000, 400, 250]),
                  ],
                },
              ],
            },
            {
              'protocol_name': 'http_hls',
              'format': [
                {
                  'format_name': 'fmp4',
                  'codec': [
                    codec('avc', [10000, 400, 250]),
                    codec('hevc', [20000, 10000, 400, 250]),
                  ],
                },
              ],
            },
          ],
        },
      },
    };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
