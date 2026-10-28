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
      expect(container.read(historyProvider).items.isLoading, true);
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
        expect(container.read(historyProvider).items.isLoading, true);
        final next = controller.search('new');
        repository.calls.last.result.complete(
          const WatchHistoryPage([], hasMore: false),
        );
        await next;
        expect(container.read(historyProvider).items.requireValue, isEmpty);
      },
    );
  }
}
