import 'dart:convert';
import 'dart:io';

import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_item_index.dart';
import 'package:bilisail/features/feed/application/filtered_feed_index.dart';

VideoSummary _video(int index) => VideoSummary(
  id: VideoId('video$index'),
  title: '${'普通视频标题素材' * 15}$index',
  coverUrl: '',
  author: 'UP',
  duration: const Duration(minutes: 3),
  playCount: 100000,
  likeCount: 5000,
  categoryName: '知识',
);

Map<String, Object> _probe(int existing, String mode) {
  final filter = RecommendationFilter(
    mode == 'enabled'
        ? RecommendationSettings(
            titleKeywords: List.generate(32, (index) => '${'z' * 60}$index'),
            categoryKeywords: List.generate(32, (index) => '${'q' * 60}$index'),
            minimumLikeRatio: 2,
            minimumPlayCount: 1000,
            minimumDurationSeconds: 60,
          )
        : const RecommendationSettings.defaults(),
  );
  final merge = mode == 'baseline'
      ? FeedItemIndex().merge
      : FilteredFeedIndex(filter, RecommendationSurface.recommended).merge;
  var items = merge(List.generate(existing, _video));
  final micros = <int>[];
  for (var batch = 0; batch < 600; batch++) {
    // Model allocation is outside the timed page merge for all three modes.
    final incoming = List.generate(
      20,
      (item) => _video(existing + batch * 20 + item),
    );
    final watch = Stopwatch()..start();
    items = merge(incoming);
    watch.stop();
    if (batch >= 100) micros.add(watch.elapsedMicroseconds);
  }
  micros.sort();
  return {
    'initial': existing,
    'mode': mode,
    'pageSize': 20,
    'samples': micros.length,
    'medianUs': micros[micros.length ~/ 2],
    'p95Us': micros[(micros.length * .95).floor()],
    'maxUs': micros.last,
    'finalCount': items.length,
  };
}

void main() {
  // This measures data processing, not Flutter frame time or device scrolling.
  for (final mode in ['baseline', 'disabled', 'enabled']) {
    _probe(1000, mode);
  }
  stdout.writeln(
    jsonEncode([
      for (final initial in [1000, 10000])
        for (final mode in ['baseline', 'disabled', 'enabled'])
          _probe(initial, mode),
    ]),
  );
}
