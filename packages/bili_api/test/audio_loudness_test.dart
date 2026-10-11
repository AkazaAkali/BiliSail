import 'dart:convert';
import 'dart:typed_data';
import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _volume = {
  'measured_i': -16.7,
  'multi_scene_args': {
    'normal_target_i': '-14',
    'high_dynamic_target_i': '-24',
    'undersized_target_i': '-28',
  },
};

final class _Transport implements ApiTransport {
  Object? volume = _volume;
  final requests = <Uri>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    requests.add(uri);
    final nav = uri.path.endsWith('/nav');
    final data = nav
        ? {
            'wbi_img': {
              'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
              'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
            },
          }
        : {
            'volume': volume,
            'accept_quality': [80],
            'dash': {
              'duration': 60,
              'video': [
                {
                  'id': 80,
                  'baseUrl': 'https://cdn.example/v.m4s',
                  'codecs': 'avc1',
                  'mimeType': 'video/mp4',
                  'bandwidth': 1000,
                },
              ],
              'audio': [
                {
                  'id': 30280,
                  'baseUrl': 'https://cdn.example/a.m4s',
                  'codecs': 'mp4a.40.2',
                  'mimeType': 'audio/mp4',
                  'bandwidth': 128,
                },
              ],
            },
          };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'code': 0,
            uri.path.startsWith('/pgc/') ? 'result' : 'data': data,
          }),
        ),
      ),
      const {},
    );
  }
}

void main() {
  test(
    'UGC and PGC request and parse normalization metadata; previews do not',
    () async {
      final transport = _Transport();
      final api = BiliApiClient(transport: transport);
      final ugc = await api.getPlayInfo('BV1GJ411x7h7', '137649199');
      final pgc = await PgcClient(api).getPlayInfo('1');
      for (final info in [ugc, pgc]) {
        expect(info.loudness?.measuredI, -16.7);
        expect(info.loudness?.normalTargetI, -14);
        expect(info.loudness?.highDynamicTargetI, -24);
        expect(info.loudness?.undersizedTargetI, -28);
      }
      final plays = transport.requests.where(
        (u) => u.path.endsWith('/playurl'),
      );
      expect(plays.length, 2);
      expect(
        plays.every((u) => u.queryParameters['voice_balance'] == '1'),
        isTrue,
      );
      expect(plays.first.queryParameters['w_rid'], isNotEmpty);
      await api.getVideoPreviewInfo('BV1GJ411x7h7', '137649199');
      expect(
        transport.requests.last.queryParameters.containsKey('voice_balance'),
        isFalse,
      );
    },
  );
  test(
    'optional invalid metadata never makes a playable source fail',
    () async {
      final transport = _Transport();
      final api = BiliApiClient(transport: transport);
      for (final value in [
        null,
        [],
        {},
        {'measured_i': -20},
        {..._volume, 'measured_i': 'NaN'},
        {..._volume, 'measured_i': .001},
        {
          ..._volume,
          'multi_scene_args': {
            'normal_target_i': '-14',
            'high_dynamic_target_i': '-24',
          },
        },
      ]) {
        transport.volume = value;
        expect(
          (await api.getPlayInfo('BV1GJ411x7h7', '137649199')).loudness,
          isNull,
        );
        expect((await PgcClient(api).getPlayInfo('1')).loudness, isNull);
      }
      expect(
        ApiAudioLoudness.parse({..._volume, 'measured_i': '-16.7'})?.measuredI,
        -16.7,
      );
    },
  );
}
