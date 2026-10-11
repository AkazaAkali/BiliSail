import '../../../domain/video.dart';

/// A read-only snapshot of the selected watch-later subtab at navigation time.
final class WatchLaterQueue {
  WatchLaterQueue({
    required this.id,
    required this.scope,
    required this.sessionEpoch,
    required List<WatchLaterQueueItem> items,
  }) : items = List.unmodifiable(items);

  final String id;
  final String scope;
  final int sessionEpoch;
  final List<WatchLaterQueueItem> items;

  /// Keep the current source navigable if another page removes it while playing.
  WatchLaterQueue withoutRemoved(Set<String> removed, {VideoId? current}) {
    if (!items.any(
      (item) => item.video.id != current && removed.contains(item.removalId),
    )) {
      return this;
    }
    return WatchLaterQueue(
      id: id,
      scope: scope,
      sessionEpoch: sessionEpoch,
      items: [
        for (final item in items)
          if (item.video.id == current || !removed.contains(item.removalId))
            item,
      ],
    );
  }

  int indexOf(VideoId id) => items.indexWhere((item) => item.video.id == id);
  WatchLaterQueueItem? adjacent(VideoId id, int direction) {
    final current = indexOf(id);
    if (current < 0) return null;
    final index = current + direction;
    return index >= 0 && index < items.length ? items[index] : null;
  }
}

final class WatchLaterQueueItem {
  const WatchLaterQueueItem({
    required this.video,
    this.entryId,
    this.aid,
    this.playCountText = '',
    this.danmakuCountText = '',
  });

  final VideoSummary video;
  final String? entryId, aid;
  String get removalId => entryId ?? video.id.value;
  final String playCountText;
  final String danmakuCountText;
}
