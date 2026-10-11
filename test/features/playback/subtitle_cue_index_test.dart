import 'dart:math';

import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/domain/subtitle_cue_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unordered overlaps preserve source priority and half-open boundaries',
    () {
      const cues = [
        SubtitleCue(Duration(seconds: 3), Duration(seconds: 5), 'first'),
        SubtitleCue(Duration(seconds: 1), Duration(seconds: 7), 'second'),
        SubtitleCue(Duration(seconds: 2), Duration(seconds: 4), 'third'),
        SubtitleCue(Duration(seconds: 5), Duration(seconds: 5), 'empty'),
        SubtitleCue(Duration(seconds: 8), Duration(seconds: 7), 'invalid'),
        SubtitleCue(Duration(seconds: 9), Duration(seconds: 10), 'last'),
      ];
      final index = SubtitleCueIndex(cues);
      for (final second in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 4, 0, 9]) {
        final position = Duration(seconds: second);
        expect(index.at(position), same(_linear(cues, position)));
      }
      expect(index.intervalCount, 6);
    },
  );

  for (final length in [500, 5000, 20000]) {
    test('$length cues match linear order across playback, gaps and seeks', () {
      final random = Random(length);
      final cues = List.generate(length, (i) {
        final start = Duration(milliseconds: i * 100);
        return SubtitleCue(
          start,
          start + Duration(milliseconds: i % 3 == 0 ? 75 : 170),
          '$i',
        );
      })..shuffle(random);
      final index = SubtitleCueIndex(cues);
      final positions = [
        for (var i = 0; i < 300; i++) Duration(milliseconds: i * length ~/ 3),
        for (var i = 0; i < 300; i++)
          Duration(milliseconds: random.nextInt(length * 100 + 100)),
        Duration(milliseconds: length * 100 + 100),
        Duration.zero,
      ];
      for (final position in positions) {
        expect(index.at(position), same(_linear(cues, position)));
      }
      expect(index.intervalCount, lessThanOrEqualTo(length * 2));
      expect(index.comparisonCount, lessThan(positions.length * 20));
      final lookups = index.lookupCount;
      final comparisons = index.comparisonCount;
      for (var i = 0; i < 100; i++) {
        index.at(positions.last);
      }
      expect(index.lookupCount, lookups);
      expect(index.comparisonCount, comparisons);
    });
  }

  test('sequential playback uses the cursor with constant interval work', () {
    final cues = List.generate(
      20000,
      (i) => SubtitleCue(
        Duration(seconds: i * 2),
        Duration(seconds: i * 2 + 1),
        '$i',
      ),
    );
    final index = SubtitleCueIndex(cues);
    for (var ms = 0; ms < 10000; ms += 10) {
      final position = Duration(milliseconds: ms);
      expect(index.at(position), same(_linear(cues, position)));
    }
    expect(index.comparisonCount, lessThan(2050));
  });

  test('empty and shared cue instances remain valid across gaps', () {
    expect(SubtitleCueIndex(const []).at(Duration.zero), isNull);
    const cue = SubtitleCue(Duration.zero, Duration(seconds: 1), 'same');
    final index = SubtitleCueIndex(const [cue, cue]);
    expect(index.at(Duration.zero), same(cue));
    expect(index.at(const Duration(seconds: 1)), isNull);
    expect(index.at(Duration.zero), same(cue));
  });
}

SubtitleCue? _linear(List<SubtitleCue> cues, Duration position) => cues
    .where((cue) => position >= cue.start && position < cue.end)
    .firstOrNull;
