import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/library_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) =>
      throw UnimplementedError('LibraryRepository must be provided by app'),
);

final historyProvider =
    NotifierProvider.autoDispose<HistoryController, HistoryState>(
      HistoryController.new,
    );

final class HistoryState {
  const HistoryState({
    this.query = '',
    this.preview = false,
    this.refreshing = false,
    this.refreshError,
    this.items = const AsyncLoading(),
    this.hasMore = false,
    this.loadingMore = false,
    this.pageError,
    this.limitReached = false,
    this.writeBusy = false,
    this.writeUncertain = false,
  });
  final String query;
  final bool preview, refreshing;
  final Object? refreshError;
  final AsyncValue<List<WatchHistoryEntry>> items;
  final bool hasMore, loadingMore, limitReached;
  final Object? pageError;
  final bool writeBusy, writeUncertain;

  HistoryState withWrite({required bool busy, bool? uncertain}) => HistoryState(
    query: query,
    preview: preview,
    refreshError: refreshError,
    items: items,
    hasMore: hasMore,
    pageError: pageError,
    limitReached: limitReached,
    writeBusy: busy,
    writeUncertain: uncertain ?? writeUncertain,
  );
}

final class HistoryController extends Notifier<HistoryState> {
  static const maxEntries = 500;
  RequestCancellation? _cancellation;
  int _generation = 0;
  String? _cursor;
  final Set<String> _seenCursors = {};
  int _emptyPages = 0;
  String _scope = '';
  int _epoch = 0;
  List<WatchHistoryEntry> _cachedEntries = const [];

  @override
  HistoryState build() {
    ref.watch(libraryRepositoryProvider);
    _cachedEntries = const [];
    ref.onDispose(() {
      _generation++;
      _cancellation?.cancel();
    });
    Future<void>.microtask(refresh);
    return const HistoryState();
  }

  bool _current(int generation, RequestCancellation cancellation) =>
      ref.mounted &&
      generation == _generation &&
      !cancellation.isCancelled &&
      _scope == ref.read(libraryRepositoryProvider).accountScope &&
      _epoch == ref.read(sessionEpochProvider)();

  void _validateCursor(WatchHistoryPage page) {
    if (page.hasMore &&
        (page.nextCursor == null || _seenCursors.contains(page.nextCursor))) {
      throw const AppFailure(AppFailureKind.protocol, '历史分页游标没有前进，请刷新重试');
    }
  }

  List<WatchHistoryEntry> _merge(
    List<WatchHistoryEntry> before,
    List<WatchHistoryEntry> incoming, {
    bool newestFirst = false,
  }) {
    final entries = <(String, String, String?), WatchHistoryEntry>{};
    for (final entry in [...before, ...incoming]) {
      final key = (entry.video.id.value, entry.part.cid, entry.episodeId);
      final old = entries[key];
      if (old == null || entry.watchedAt.isAfter(old.watchedAt)) {
        entries[key] = entry;
      }
    }
    final ordered = entries.values.toList();
    if (newestFirst) ordered.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    return List.unmodifiable(ordered.take(maxEntries));
  }

  void _accept(
    WatchHistoryPage page,
    List<WatchHistoryEntry> items,
    int beforeCount,
  ) {
    // Memory-only, bounded to records already fetched for this account.
    _cachedEntries = _merge(page.items, _cachedEntries, newestFirst: true);
    _cursor = page.nextCursor;
    if (_cursor case final cursor?) _seenCursors.add(cursor);
    _emptyPages = items.length == beforeCount ? _emptyPages + 1 : 0;
    final limit = items.length >= maxEntries;
    state = HistoryState(
      query: state.query,
      items: AsyncData(items),
      hasMore: page.hasMore && !limit,
      limitReached: limit,
      pageError: page.hasMore && !limit && _emptyPages >= 3
          ? const AppFailure(AppFailureKind.protocol, '连续多页没有视频记录，可重试继续加载')
          : null,
    );
  }

  Future<void> search(String input) => _refresh(input.trim());

  Future<void> refresh() => _refresh(state.query);

  Future<WatchHistoryPage> _loadPage({
    String? cursor,
    required RequestCancellation cancellation,
  }) {
    final repository = ref.read(libraryRepositoryProvider);
    if (state.query.isEmpty) {
      return repository.loadHistory(cursor: cursor, cancellation: cancellation);
    }
    if (repository is! WatchHistorySearch) {
      throw const AppFailure(AppFailureKind.protocol, '观看历史搜索暂不可用');
    }
    return (repository as WatchHistorySearch).searchHistory(
      keyword: state.query,
      cursor: cursor,
      cancellation: cancellation,
    );
  }

  Future<void> _refresh(String query) async {
    if (!ref.mounted || state.writeBusy) return;
    final uncertain = state.writeUncertain;
    final generation = ++_generation;
    _cancellation?.cancel();
    final cancellation = RequestCancellation();
    _cancellation = cancellation;
    _cursor = null;
    _seenCursors.clear();
    _emptyPages = 0;
    final scope = ref.read(libraryRepositoryProvider).accountScope;
    final epoch = ref.read(sessionEpochProvider)();
    if (_scope != scope || _epoch != epoch) _cachedEntries = const [];
    _scope = scope;
    _epoch = epoch;
    final needle = query.toLowerCase();
    final preview = _cachedEntries
        .where(
          (entry) =>
              needle.isEmpty ||
              entry.video.title.toLowerCase().contains(needle) ||
              entry.video.author.toLowerCase().contains(needle) ||
              entry.part.title.toLowerCase().contains(needle),
        )
        .toList(growable: false);
    final showPreview = query.isNotEmpty || _cachedEntries.isNotEmpty;
    state = HistoryState(
      query: query,
      items: showPreview ? AsyncData(preview) : const AsyncLoading(),
      preview: showPreview,
      refreshing: showPreview,
      writeUncertain: uncertain,
    );
    try {
      final page = await _loadPage(cancellation: cancellation);
      if (!_current(generation, cancellation)) return;
      _validateCursor(page);
      _accept(page, _merge(const [], page.items), 0);
    } catch (error, stack) {
      if (!_current(generation, cancellation) ||
          error is AppFailure && error.kind == AppFailureKind.cancelled) {
        return;
      }
      state = HistoryState(
        query: state.query,
        items: showPreview ? AsyncData(preview) : AsyncError(error, stack),
        preview: showPreview,
        refreshError: showPreview ? error : null,
        writeUncertain: uncertain,
      );
    }
  }

  Future<void> loadMore() async {
    final items = state.items.asData?.value;
    final cancellation = _cancellation;
    if (items == null ||
        cancellation == null ||
        !state.hasMore ||
        state.loadingMore) {
      return;
    }
    if (state.writeBusy || state.writeUncertain) return;
    final generation = _generation;
    if (!_current(generation, cancellation)) return;
    _emptyPages = state.pageError == null ? _emptyPages : 0;
    state = HistoryState(
      query: state.query,
      items: AsyncData(items),
      hasMore: true,
      loadingMore: true,
    );
    try {
      final page = await _loadPage(cursor: _cursor, cancellation: cancellation);
      if (!_current(generation, cancellation)) return;
      _validateCursor(page);
      _accept(page, _merge(items, page.items), items.length);
    } catch (error) {
      if (!_current(generation, cancellation) ||
          error is AppFailure && error.kind == AppFailureKind.cancelled) {
        return;
      }
      state = HistoryState(
        query: state.query,
        items: AsyncData(items),
        hasMore: true,
        pageError: error,
      );
    }
  }

  Future<bool> delete(WatchHistoryEntry entry) async {
    final key = entry.deletionKey;
    if (key == null || !RegExp(r'^(archive|pgc)_[1-9][0-9]*$').hasMatch(key)) {
      throw const AppFailure(AppFailureKind.protocol, '该记录缺少历史标识，请刷新后重试');
    }
    if (!(state.items.asData?.value.contains(entry) ?? false)) return false;
    return _write(key);
  }

  Future<bool> clear() => _write(null);

  Future<bool> _write(String? deletionKey) async {
    if (!ref.mounted ||
        state.writeBusy ||
        state.preview ||
        state.items.asData == null) {
      return false;
    }
    if (state.writeUncertain) throw const HistoryWriteUncertain();
    final repository = ref.read(libraryRepositoryProvider);
    if (repository is! WatchHistoryMutations) {
      throw const AppFailure(AppFailureKind.protocol, '历史操作暂不可用');
    }
    final previous = _cancellation;
    if (previous == null || !_current(_generation, previous)) return false;
    // Invalidate reads before writing: a late page must not restore a deletion.
    final generation = ++_generation;
    previous.cancel();
    final cancellation = RequestCancellation();
    _cancellation = cancellation;
    state = state.withWrite(busy: true);
    try {
      final mutations = repository as WatchHistoryMutations;
      if (deletionKey == null) {
        await mutations.clearHistory(cancellation: cancellation);
      } else {
        await mutations.deleteHistory(deletionKey, cancellation: cancellation);
      }
      if (!_current(generation, cancellation)) return false;
      _cachedEntries = deletionKey == null
          ? const []
          : _cachedEntries
                .where((entry) => entry.deletionKey != deletionKey)
                .toList(growable: false);
      if (deletionKey == null) {
        _cursor = null;
        _seenCursors.clear();
        _emptyPages = 0;
        state = HistoryState(query: state.query, items: const AsyncData([]));
      } else {
        final items = state.items.requireValue;
        state = HistoryState(
          query: state.query,
          items: AsyncData(
            List.unmodifiable(
              items.where((entry) => entry.deletionKey != deletionKey),
            ),
          ),
          hasMore: state.hasMore,
          pageError: state.pageError,
          limitReached: state.limitReached,
        );
        // Search uses offset pages: deletion shifts later pages left. Reload
        // from page one rather than skipping a result with the old page number.
        if (state.query.isNotEmpty) await refresh();
      }
      return true;
    } on HistoryWriteUncertain {
      if (!_current(generation, cancellation)) return false;
      // Unknown writes must not seed a later optimistic preview.
      _cachedEntries = const [];
      state = state.withWrite(busy: false, uncertain: true);
      rethrow;
    } on AppFailure catch (failure) {
      if (!_current(generation, cancellation) ||
          failure.kind == AppFailureKind.cancelled) {
        return false;
      }
      rethrow;
    } finally {
      if (_current(generation, cancellation) && state.writeBusy) {
        state = state.withWrite(busy: false);
      }
    }
  }
}
