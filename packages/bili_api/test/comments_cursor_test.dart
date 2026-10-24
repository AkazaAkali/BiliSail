import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

Map<String, Object?> comment(
  String id, {
  int state = 0,
  bool invisible = false,
}) => {
  'rpid_str': id,
  'member': {'uname': 'fixture'},
  'content': {'message': 'fixture'},
  'state': state,
  'invisible': invisible,
};

void main() {
  test(
    'WBI comments keep restricted entries, pinned IDs and opaque cursors',
    () async {
      final transport = _Transport();
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final first = await api.getVideoCommentsByCursor('9007199254740993');
      final request = transport.requests.last;
      expect(request.path, '/x/v2/reply/wbi/main');
      expect(request.queryParameters['oid'], '9007199254740993');
      expect(request.queryParameters['type'], '1');
      expect(request.queryParameters['mode'], '3');
      expect(request.queryParameters['pagination_str'], '{"offset":""}');
      expect(request.queryParameters['w_rid'], isNotEmpty);
      expect(first.items.map((c) => c.id), ['50', '51']);
      expect(first.items.last.state, 17);
      expect(first.items.last.invisible, false);
      expect(first.nextCursor, transport.nextOffset);
      expect(first.totalCount, 42);
      expect(first.hasMore, true);

      final cursor = first.nextCursor!;
      transport.data = {
        'top_replies': [comment('50')],
        'replies': [comment('52', invisible: true)],
        'cursor': {'is_end': true, 'all_count': 42},
      };
      final next = await api.getVideoCommentsByCursor(
        '9007199254740993',
        cursor: cursor,
        sort: ApiCommentSort.latest,
      );
      expect(transport.requests.last.queryParameters['mode'], '2');
      expect(
        jsonDecode(transport.requests.last.queryParameters['pagination_str']!),
        {'offset': cursor},
      );
      expect(next.items.single.id, '52');
      expect(next.items.single.invisible, true);
      expect(next.hasMore, false);
      expect(next.nextCursor, isNull);
      expect(
        transport.requests.where((u) => u.path.endsWith('/nav')),
        hasLength(1),
      );
    },
  );

  test('empty cursor pages end without fabricating page numbers', () async {
    final transport = _Transport()
      ..data = {
        'cursor': {'is_end': false, 'all_count': 0},
        'replies': null,
      };
    final result = await BiliApiClient(
      transport: transport,
    ).getVideoCommentsByCursor('42');
    expect(result.items, isEmpty);
    expect(result.hasMore, false);
    expect(result.nextCursor, isNull);
  });

  for (final next in [null, '', 1]) {
    test('nonterminal pages reject invalid cursor $next', () async {
      final transport = _Transport()
        ..data = {
          'replies': [comment('51')],
          'cursor': {
            'is_end': false,
            'pagination_reply': {'next_offset': next},
          },
        };
      await expectLater(
        BiliApiClient(
          transport: transport,
        ).getVideoCommentsByCursor('42', cursor: 'same'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    });
  }

  test(
    'hot pages may return a repeated opaque cursor with different entries',
    () async {
      final transport = _Transport()
        ..data = {
          'replies': [comment('52')],
          'cursor': {
            'is_end': false,
            'pagination_reply': {'next_offset': 'same'},
          },
        };
      final result = await BiliApiClient(
        transport: transport,
      ).getVideoCommentsByCursor('42', cursor: 'same');
      expect(result.items.single.id, '52');
      expect(result.nextCursor, 'same');
      expect(result.hasMore, true);
    },
  );

  test('invalid caller cursors and IDs do not reach transport', () async {
    final transport = _Transport();
    final api = BiliApiClient(transport: transport);
    for (final cursor in ['', 'x' * 4097]) {
      await expectLater(
        api.getVideoCommentsByCursor('42', cursor: cursor),
        throwsArgumentError,
      );
    }
    await expectLater(api.getVideoCommentsByCursor('1.2'), throwsArgumentError);
    expect(transport.requests, isEmpty);
  });
}

final class _Transport implements ApiTransport {
  final requests = <Uri>[];
  final nextOffset = 'opaque+/%="\\cursor';
  late Map<String, Object?> data = {
    'top_replies': [comment('50')],
    'upper': {'top': comment('50')},
    'replies': [comment('50'), comment('51', state: 17)],
    'cursor': {
      'is_end': false,
      'all_count': 42,
      'pagination_reply': {'next_offset': nextOffset},
    },
  };

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    requests.add(uri);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'code': 0,
            'data': uri.path.endsWith('/nav')
                ? {
                    'wbi_img': {
                      'img_url':
                          'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
                      'sub_url':
                          'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
                    },
                  }
                : data,
          }),
        ),
      ),
      const {},
    );
  }
}
