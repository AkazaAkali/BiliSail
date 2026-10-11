import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_item_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'updates keep stable order without changing previously published lists',
    () {
      final index = FeedItemIndex();
      final original = index.merge(List.generate(500, _video));
      final update = _video(5, title: 'updated');
      final next = index.merge([
        update,
        _video(500),
        _video(129),
        _video(500, title: 'last'),
      ]);
      expect(next, hasLength(501));
      expect(next[5], same(update));
      expect(next[500].title, 'last');
      expect(original[5].title, 'Video 5');
      expect(original, hasLength(500));
      expect(next[128], same(original[128]));
      expect(() => next[0] = update, throwsUnsupportedError);
      expect(() => next.add(update), throwsUnsupportedError);
      expect(() => next.length = 0, throwsUnsupportedError);
      expect(() => next[-1], throwsRangeError);
      expect(() => next[501], throwsRangeError);
    },
  );

  test('first-page duplicates use the last value at the first position', () {
    final index = FeedItemIndex();
    final items = index.merge([
      _video(1),
      _video(2),
      _video(1, title: 'replacement'),
    ]);
    expect(items.map((v) => v.id.value), ['1', '2']);
    expect(items.first.title, 'replacement');
    expect(index.merge([]), same(items));
    expect(index.merge([items.first]), same(items));
  });

  test('500 pages retain all 10000 items and isolated query snapshots', () {
    final index = FeedItemIndex();
    final first = index.merge(List.generate(20, _video));
    var current = first;
    for (var page = 1; page < 500; page++) {
      current = index.merge(List.generate(20, (i) => _video(page * 20 + i)));
    }
    expect(current, hasLength(10000));
    expect(current.map((v) => v.id.value), List.generate(10000, (i) => '$i'));
    expect(first, hasLength(20));
    final other = FeedItemIndex().merge([_video(0, title: 'other query')]);
    expect(current.first.title, 'Video 0');
    expect(other.first.title, 'other query');
  });
}

VideoSummary _video(int i, {String? title}) => VideoSummary(
  id: VideoId('$i'),
  title: title ?? 'Video $i',
  author: 'author',
  coverUrl: '',
  duration: const Duration(minutes: 1),
);
