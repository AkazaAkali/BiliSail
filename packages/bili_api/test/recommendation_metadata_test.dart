import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'optional metadata keeps unknown counts and explicit follow status',
    () async {
      final transport = _Transport();
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      for (final (value, expected) in <(Object?, bool?)>[
        (null, null),
        (1, true),
        (0, false),
        (true, true),
        (false, false),
        ('1', null),
        ('已关注', null),
      ]) {
        transport.followed = value;
        final item = (await api.getRelatedVideos('BV1234567890')).single;
        expect(item.isFollowed, expected);
        expect(item.likeCount, isNull);
        expect(item.playCount, isNull);
        expect(item.categoryName, isNull);
      }
    },
  );
}

final class _Transport implements ApiTransport {
  Object? followed;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
    200,
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'code': 0,
          'data': [
            {
              'bvid': 'BV1234567890',
              'title': '视频',
              'duration': 60,
              'is_followed': followed,
              'rcmd_reason': {'content': '已关注'},
            },
          ],
        }),
      ),
    ),
    const {},
  );
}
