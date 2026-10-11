import 'dart:collection';

import 'playback_repository.dart';

/// Disjoint display intervals with the first matching cue in source order.
/// Sorting cues themselves would change overlapping or unordered subtitles.
final class SubtitleCueIndex {
  SubtitleCueIndex(List<SubtitleCue> cues) {
    final boundaries = <({Duration at, int cue, bool start})>[];
    for (var i = 0; i < cues.length; i++) {
      final cue = cues[i];
      if (cue.end <= cue.start) continue;
      boundaries.add((at: cue.start, cue: i, start: true));
      boundaries.add((at: cue.end, cue: i, start: false));
    }
    boundaries.sort((a, b) => a.at.compareTo(b.at));
    final active = SplayTreeSet<int>();
    SubtitleCue? previous;
    var i = 0;
    while (i < boundaries.length) {
      final at = boundaries[i].at;
      do {
        final boundary = boundaries[i++];
        if (boundary.start) {
          active.add(boundary.cue);
        } else {
          active.remove(boundary.cue);
        }
      } while (i < boundaries.length && boundaries[i].at == at);
      final selected = active.isEmpty ? null : cues[active.first];
      if (!identical(previous, selected)) {
        _runs.add((at: at, cue: selected));
        previous = selected;
      }
    }
  }

  final _runs = <({Duration at, SubtitleCue? cue})>[];
  int _cursor = -1;
  Duration? _position;
  SubtitleCue? _cue;
  int _lookupCount = 0;
  int _comparisonCount = 0;

  /// Local structural counters; no subtitle text or timestamps are logged.
  int get lookupCount => _lookupCount;
  int get comparisonCount => _comparisonCount;
  int get intervalCount => _runs.length;

  bool _atOrBefore(int index, Duration position) {
    _comparisonCount++;
    return _runs[index].at <= position;
  }

  SubtitleCue? at(Duration position) {
    // Buffer, volume and other snapshot changes do not repeat a lookup.
    if (_position == position) return _cue;
    _lookupCount++;
    _position = position;
    if (_runs.isEmpty) return _cue = null;

    // Ordinary playback stays in this interval or advances by one boundary.
    if (_cursor >= 0 && _atOrBefore(_cursor, position)) {
      final next = _cursor + 1;
      if (next == _runs.length || !_atOrBefore(next, position)) {
        return _cue;
      }
      if (next + 1 == _runs.length || !_atOrBefore(next + 1, position)) {
        _cursor = next;
        return _cue = _runs[next].cue;
      }
    }
    var low = 0;
    var high = _runs.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_atOrBefore(middle, position)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _cursor = low - 1;
    return _cue = _cursor < 0 ? null : _runs[_cursor].cue;
  }
}
