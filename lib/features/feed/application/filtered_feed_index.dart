import '../../../domain/recommendation_settings.dart';
import '../../../domain/video.dart';
import 'feed_item_index.dart';

/// Keeps the original page metadata so changing a local rule needs no reads.
/// With no rules, there is only the existing chunked index and its snapshot.
final class FilteredFeedIndex {
  FilteredFeedIndex(this._filter, this.surface);

  final RecommendationSurface surface;
  final _raw = FeedItemIndex();
  FeedItemIndex? _visible;
  RecommendationFilter _filter;
  Set<VideoId> _previousIds = const {};
  int? previousStartIndex;

  List<VideoSummary> get rawItems => _raw.items;
  List<VideoSummary> get items => _visible?.items ?? _raw.items;

  void configure(RecommendationFilter filter) {
    if (filter.settings.filterKey == _filter.settings.filterKey) return;
    _filter = filter;
    _visible = filter.enabledFor(surface)
        ? (FeedItemIndex()..merge(_raw.items.where(_allows).toList()))
        : null;
    _locatePrevious();
  }

  bool _allows(VideoSummary item) => _filter.allows(item, surface);

  List<VideoSummary> merge(List<VideoSummary> incoming) {
    if (!_filter.enabledFor(surface)) return _raw.merge(incoming);
    // Seed from the pre-merge snapshot only when rules first become active.
    final visible = _visible ??= FeedItemIndex()
      ..merge(_raw.items.where(_allows).toList());
    _raw.merge(incoming);
    final accepted = <VideoSummary>[];
    final excluded = <VideoId>{};
    final latest = {for (final item in incoming) item.id: item};
    for (final item in latest.values) {
      if (_allows(item)) {
        accepted.add(item);
      } else {
        excluded.add(item.id);
      }
    }
    final previousLength = visible.items.length;
    visible.remove(excluded);
    final removed = previousLength != visible.items.length;
    final result = visible.merge(accepted);
    if (removed) _locatePrevious();
    return result;
  }

  void markPrevious(Iterable<VideoId> ids) {
    _previousIds = Set.unmodifiable(ids.take(200));
    _locatePrevious();
  }

  void _locatePrevious() {
    final index = _previousIds.isEmpty
        ? -1
        : items.indexWhere((item) => _previousIds.contains(item.id));
    previousStartIndex = index < 0 ? null : index;
  }
}
