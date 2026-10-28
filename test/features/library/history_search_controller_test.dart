import 'dart:async';

import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/library/application/library_controller.dart';
import 'package:bilisail/features/library/domain/library_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_controller_test.dart' show entry;

class SearchRepository
    implements LibraryRepository, WatchHistorySearch, WatchHistoryMutations {
  Completer<void>? pendingWrite;
  @override
  Future<void> deleteHistory(
    String deletionKey, {
    required RequestCancellation cancellation,
  }) async {
    await pendingWrite?.future;
  }

  @override
  Future<void> clearHistory({
    required RequestCancellation cancellation,
  }) async {}

  @override
  String accountScope = 'user:1';
  final calls =
      <
        ({
          String query,
          String? cursor,
          RequestCancellation token,
          Completer<WatchHistoryPage> result,
        })
      >[];

  Future<WatchHistoryPage> _load(
    String query,
    String? cursor,
    RequestCancellation token,
  ) {
    final result = Completer<WatchHistoryPage>();
    calls.add((query: query, cursor: cursor, token: token, result: result));
    return result.future;
  }

  @override
  Future<WatchHistoryPage> loadHistory({
    String? cursor,
    required RequestCancellation cancellation,
  }) => _load('', cursor, cancellation);

  @override
  Future<WatchHistoryPage> searchHistory({
    required String keyword,
    String? cursor,
    required RequestCancellation cancellation,
  }) => _load(keyword, cursor, cancellation);
}

void main() {
  late SearchRepository repository;
  late ProviderContainer container;
  var epoch = 0;
  setUp(() async {
    epoch = 0;
    repository = SearchRepository();
    container = ProviderContainer(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(repository),
        sessionEpochProvider.overrideWithValue(() => epoch),
      ],
    );
    container.listen(historyProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    repository.calls.single.result.complete(
      WatchHistoryPage([entry('1')], hasMore: true, nextCursor: 'browse'),
    );
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() => container.dispose());

  test(
    'search trims, pages server results, refreshes and clears to browse',
    () async {
      final controller = container.read(historyProvider.notifier);
      final search = controller.search('  视频  ');
      expect(repository.calls.last.query, '视频');
      expect(repository.calls.last.cursor, isNull);
      expect(container.read(historyProvider).preview, true);
      repository.calls.last.result.complete(
        WatchHistoryPage([entry('2')], hasMore: true, nextCursor: '2'),
      );
      await search;
      final more = controller.loadMore();
      expect(repository.calls.last.query, '视频');
      expect(repository.calls.last.cursor, '2');
      repository.calls.last.result.complete(
        WatchHistoryPage([entry('3')], hasMore: false),
      );
      await more;
      expect(
        container
            .read(historyProvider)
            .items
            .requireValue
            .map((e) => e.part.cid),
        ['2', '3'],
      );
      final refresh = controller.refresh();
      expect(repository.calls.last.query, '视频');
      expect(repository.calls.last.cursor, isNull);
      repository.calls.last.result.complete(
        const WatchHistoryPage([], hasMore: false),
      );
      await refresh;
      final clear = controller.search('  ');
      expect(repository.calls.last.query, '');
      expect(repository.calls.last.cursor, isNull);
      repository.calls.last.result.complete(
        WatchHistoryPage([entry('1')], hasMore: false),
      );
      await clear;
      expect(container.read(historyProvider).query, '');
      expect(
        container.read(historyProvider).items.requireValue.single.part.cid,
        '1',
      );
    },
  );

  test(
    'late browse page and older search cannot replace newer search',
    () async {
      final controller = container.read(historyProvider.notifier);
      final more = controller.loadMore();
      final oldPage = repository.calls.last;
      final first = controller.search('first');
      final oldSearch = repository.calls.last;
      final second = controller.search('second');
      expect(oldPage.token.isCancelled, true);
      expect(oldSearch.token.isCancelled, true);
      repository.calls.last.result.complete(
        WatchHistoryPage([entry('9')], hasMore: false),
      );
      await second;
      oldSearch.result.complete(WatchHistoryPage([entry('8')], hasMore: false));
      oldPage.result.complete(WatchHistoryPage([entry('7')], hasMore: false));
      await Future.wait([first, more]);
      expect(container.read(historyProvider).query, 'second');
      expect(
        container.read(historyProvider).items.requireValue.single.part.cid,
        '9',
      );
    },
  );

  test(
    'search deletion resets offset pagination and blocks searches during write',
    () async {
      final controller = container.read(historyProvider.notifier);
      final search = controller.search('video');
      repository.calls.last.result.complete(
        WatchHistoryPage([entry('2')], hasMore: true, nextCursor: '2'),
      );
      await search;
      repository.pendingWrite = Completer<void>();
      final deleting = controller.delete(
        container.read(historyProvider).items.requireValue.single,
      );
      await controller.search('must not replace');
      expect(container.read(historyProvider).query, 'video');
      expect(repository.calls, hasLength(2));
      repository.pendingWrite!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls.last.query, 'video');
      expect(repository.calls.last.cursor, isNull);
      repository.calls.last.result.complete(
        WatchHistoryPage([entry('3')], hasMore: false),
      );
      expect(await deleting, true);
      expect(
        container.read(historyProvider).items.requireValue.single.part.cid,
        '3',
      );
    },
  );

  test(
    'cached matches appear synchronously and cloud results correct them',
    () async {
      final controller = container.read(historyProvider.notifier);
      final search = controller.search('视频');
      expect(container.read(historyProvider).preview, true);
      expect(container.read(historyProvider).refreshing, true);
      expect(
        container.read(historyProvider).items.requireValue.single.part.cid,
        '1',
      );
      repository.calls.last.result.complete(
        WatchHistoryPage([entry('2'), entry('2')], hasMore: false),
      );
      await search;
      expect(container.read(historyProvider).preview, false);
      expect(
        container.read(historyProvider).items.requireValue.single.part.cid,
        '2',
      );
    },
  );

  test(
    'cloud failure keeps local matches and retry can confirm no results',
    () async {
      final controller = container.read(historyProvider.notifier);
      final search = controller.search('作者');
      repository.calls.last.result.completeError(StateError('offline'));
      await search;
      final failed = container.read(historyProvider);
      expect(failed.items.requireValue.single.part.cid, '1');
      expect(failed.preview, true);
      expect(failed.refreshing, false);
      expect(failed.refreshError, isA<StateError>());
      final retry = controller.refresh();
      repository.calls.last.result.complete(
        const WatchHistoryPage([], hasMore: false),
      );
      await retry;
      expect(container.read(historyProvider).preview, false);
      expect(container.read(historyProvider).items.requireValue, isEmpty);
    },
  );

  test(
    'preview cache is bounded and retains watch-date order across pages',
    () async {
      final controller = container.read(historyProvider.notifier);
      final more = controller.loadMore();
      repository.calls.last.result.complete(
        WatchHistoryPage([
          for (var i = 2; i <= 501; i++) entry('$i', day: 4),
        ], hasMore: false),
      );
      await more;
      final search = controller.search('视频');
      final preview = container.read(historyProvider).items.requireValue;
      expect(preview, hasLength(500));
      expect(preview.first.watchedAt.isAfter(preview.last.watchedAt), true);
      repository.calls.last.result.complete(
        const WatchHistoryPage([], hasMore: false),
      );
      await search;
    },
  );

  test(
    'preview records cannot cancel the confirming cloud read with a write',
    () async {
      final controller = container.read(historyProvider.notifier);
      final search = controller.search('视频');
      final pending = repository.calls.last;
      expect(
        await controller.delete(
          container.read(historyProvider).items.requireValue.single,
        ),
        false,
      );
      expect(await controller.clear(), false);
      expect(pending.token.isCancelled, false);
      pending.result.complete(WatchHistoryPage([entry('1')], hasMore: false));
      await search;
      final restore = controller.search('');
      expect(
        await controller.delete(
          container.read(historyProvider).items.requireValue.single,
        ),
        false,
      );
      expect(repository.calls.last.token.isCancelled, false);
      repository.calls.last.result.complete(
        WatchHistoryPage([entry('1')], hasMore: true, nextCursor: 'restored'),
      );
      await restore;
      expect(container.read(historyProvider).preview, false);
      expect(container.read(historyProvider).hasMore, true);
    },
  );

  test('empty local match remains unconfirmed until cloud completes', () async {
    final controller = container.read(historyProvider.notifier);
    final search = controller.search('not fetched');
    expect(container.read(historyProvider).items.requireValue, isEmpty);
    expect(container.read(historyProvider).preview, true);
    repository.calls.last.result.complete(
      WatchHistoryPage([entry('3')], hasMore: false),
    );
    await search;
    expect(
      container.read(historyProvider).items.requireValue.single.part.cid,
      '3',
    );
  });

  test(
    'delete and clear invalidate preview records without fetching extra pages',
    () async {
      final controller = container.read(historyProvider.notifier);
      expect(
        await controller.delete(
          container.read(historyProvider).items.requireValue.single,
        ),
        true,
      );
      final search = controller.search('视频');
      expect(container.read(historyProvider).items.requireValue, isEmpty);
      expect(repository.calls, hasLength(2));
      repository.calls.last.result.complete(
        WatchHistoryPage([entry('2')], hasMore: false),
      );
      await search;
      expect(await controller.clear(), true);
      final again = controller.search('视频');
      expect(container.read(historyProvider).items.requireValue, isEmpty);
      repository.calls.last.result.complete(
        const WatchHistoryPage([], hasMore: false),
      );
      await again;
    },
  );

  for (final changeAccount in [true, false]) {
    test(
      'search rejects stale ${changeAccount ? 'account' : 'epoch'} response',
      () async {
        final controller = container.read(historyProvider.notifier);
        final search = controller.search('old');
        if (changeAccount) {
          repository.accountScope = 'user:2';
        } else {
          epoch++;
        }
        repository.calls.last.result.complete(
          WatchHistoryPage([entry('9')], hasMore: false),
        );
        await search;
        expect(container.read(historyProvider).preview, true);
        final next = controller.search('视频');
        expect(container.read(historyProvider).items.requireValue, isEmpty);
        repository.calls.last.result.complete(
          const WatchHistoryPage([], hasMore: false),
        );
        await next;
        expect(container.read(historyProvider).items.requireValue, isEmpty);
      },
    );
  }
}
