import 'dart:collection';

import '../../../domain/video.dart';

/// One query's append/update index. Published lists remain immutable snapshots;
/// pagination only copies the chunk directory and chunks touched by this page.
final class FeedItemIndex {
  static const _chunkSize = 128;
  final _positions = <VideoId, int>{};
  _FeedItems _snapshot = _FeedItems(const [], 0);

  List<VideoSummary> merge(List<VideoSummary> incoming) {
    if (incoming.isEmpty) return _snapshot;
    final chunks = List<List<VideoSummary>>.of(_snapshot._chunks);
    final changed = <int>{};
    var length = _snapshot.length;
    for (final item in incoming) {
      final existing = _positions[item.id];
      if (existing != null &&
          identical(_snapshotItem(chunks, existing), item)) {
        continue;
      }
      final index = existing ?? length++;
      final chunkIndex = index ~/ _chunkSize;
      if (chunkIndex == chunks.length) chunks.add(<VideoSummary>[]);
      if (changed.add(chunkIndex)) {
        chunks[chunkIndex] = List.of(chunks[chunkIndex]);
      }
      final chunk = chunks[chunkIndex];
      if (existing == null) {
        _positions[item.id] = index;
        chunk.add(item);
      } else {
        chunk[index % _chunkSize] = item;
      }
    }
    if (changed.isEmpty) return _snapshot;
    for (final index in changed) {
      chunks[index] = List.unmodifiable(chunks[index]);
    }
    return _snapshot = _FeedItems(List.unmodifiable(chunks), length);
  }

  static VideoSummary _snapshotItem(
    List<List<VideoSummary>> chunks,
    int index,
  ) => chunks[index ~/ _chunkSize][index % _chunkSize];
}

final class _FeedItems extends ListBase<VideoSummary> {
  _FeedItems(this._chunks, this._length);
  final List<List<VideoSummary>> _chunks;
  final int _length;
  @override
  int get length => _length;
  @override
  set length(int value) => throw UnsupportedError('Immutable feed snapshot');
  @override
  VideoSummary operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return FeedItemIndex._snapshotItem(_chunks, index);
  }

  @override
  void operator []=(int index, VideoSummary value) =>
      throw UnsupportedError('Immutable feed snapshot');
}
