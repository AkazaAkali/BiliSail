import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'home_client_test.dart' show Transport;
import 'watch_history_client_test.dart' show entry;

Map<String, Object?> response({
  List<Object?>? items,
  Object? hasMore = false,
  int page = 1,
}) => {
  'list': items ?? [entry()],
  'has_more': hasMore,
  'page': {'pn': page, 'total': 21},
};

WatchHistoryClient client(Map<String, Object?> data) => WatchHistoryClient(
  BiliApiClient(transport: Transport((_) => {'code': 0, 'data': data})),
);

void main() {
  test(
    'searches cloud history with one encoding and page-number pagination',
    () async {
      final transport = Transport(
        (_) => {'code': 0, 'data': response(hasMore: true)},
      );
      final result = await WatchHistoryClient(
        BiliApiClient(transport: transport),
      ).search(keyword: '  猫 & Flutter+100%  ');
      final uri = transport.requests.single;
      expect(uri.path, '/x/web-interface/history/search');
      expect(uri.queryParameters, {
        'keyword': '猫 & Flutter+100%',
        'pn': '1',
        'business': 'all',
      });
      expect(result.hasMore, isTrue);
      expect(result.nextCursor, '2');
      final item = result.items.single;
      expect(item.bvid, 'BV1234567890');
      expect(item.cid, '9007199254740995');
      expect(item.authorMid, '9007199254740993');
      expect(item.deletionKey, 'archive_9007199254740997');
      expect(item.position, const Duration(seconds: 30));
      expect(item.page, 2);
    },
  );

  test('later page preserves PGC identity and completed progress', () async {
    final result = await client(
      response(page: 2, items: [entry(business: 'pgc', progress: -1)]),
    ).search(keyword: '番剧', page: 2);
    expect(result.items.single.episodeId, '123');
    expect(result.items.single.position, const Duration(seconds: 100));
    expect(result.hasMore, isFalse);
    expect(result.nextCursor, isNull);
  });

  test(
    'empty terminal page is valid and unsupported items still advance',
    () async {
      final empty = await client(response(items: [])).search(keyword: 'none');
      expect(empty.items, isEmpty);
      expect(empty.hasMore, isFalse);
      final mixed = await client(
        response(items: [entry(business: 'live')], hasMore: true),
      ).search(keyword: 'live');
      expect(mixed.items, isEmpty);
      expect(mixed.hasMore, isTrue);
      expect(mixed.nextCursor, '2');
    },
  );

  test('invalid search input does not issue a request', () async {
    final transport = Transport((_) => {'code': 0, 'data': response()});
    final history = WatchHistoryClient(BiliApiClient(transport: transport));
    for (final keyword in ['', ' \n ']) {
      await expectLater(history.search(keyword: keyword), throwsArgumentError);
    }
    for (final page in [0, -1]) {
      await expectLater(
        history.search(keyword: 'valid', page: page),
        throwsArgumentError,
      );
    }
    expect(transport.requests, isEmpty);
  });

  final invalid = <Map<String, Object?>>[
    response(hasMore: null),
    response(hasMore: 1),
    response(hasMore: 'true'),
    response(items: [], hasMore: true),
    response(page: 2),
    response()..['page'] = {'pn': 1, 'total': -1},
    response()..['page'] = {'pn': 1.5, 'total': 1},
    response()..remove('page'),
    response()..['list'] = 'invalid',
    response(items: List.generate(21, (_) => entry())),
    response(items: [entry(progress: -2)]),
  ];
  for (var i = 0; i < invalid.length; i++) {
    test(
      'rejects malformed search payload $i with its endpoint name',
      () async {
        await expectLater(
          client(invalid[i]).search(keyword: 'fixture'),
          throwsA(
            isA<ApiFailure>()
                .having(
                  (e) => e.category,
                  'category',
                  ApiFailureCategory.protocol,
                )
                .having(
                  (e) => e.endpointId,
                  'endpoint',
                  'watch_history_search',
                ),
          ),
        );
      },
    );
  }
}
