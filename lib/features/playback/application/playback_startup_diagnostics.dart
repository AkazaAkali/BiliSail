import 'dart:collection';

enum PlaybackStartupStage {
  saveProgress,
  stopPrevious,
  resolve,
  localResumeRead,
  nativeOpen,
  playAndAudioReady,
}

/// One operation, not a first-visible-frame measurement. Native open may finish
/// before the first texture, and pause intent may skip play/audio preparation.
final class PlaybackStartupSample {
  const PlaybackStartupSample({
    required this.generation,
    required this.stage,
    required this.startedAt,
    required this.elapsed,
    required this.completed,
  });

  final int generation;
  final PlaybackStartupStage stage;
  final Duration startedAt, elapsed;
  final bool completed;
}

/// Local, bounded stage observations; never stores identities, URLs or errors.
final class PlaybackStartupDiagnostics {
  PlaybackStartupDiagnostics({Duration Function()? now}) {
    _clock.start();
    _now = now ?? () => _clock.elapsed;
  }

  final _clock = Stopwatch();
  late final Duration Function() _now;
  final _samples = ListQueue<PlaybackStartupSample>();
  static const capacity = 32;

  List<PlaybackStartupSample> get samples => List.unmodifiable(_samples);

  Future<T> measure<T>(
    int generation,
    PlaybackStartupStage stage,
    Future<T> Function() operation,
  ) async {
    final startedAt = _now();
    var completed = false;
    try {
      final result = await operation();
      completed = true;
      return result;
    } finally {
      if (_samples.length == capacity) _samples.removeFirst();
      _samples.add(
        PlaybackStartupSample(
          generation: generation,
          stage: stage,
          startedAt: startedAt,
          elapsed: _now() - startedAt,
          completed: completed,
        ),
      );
    }
  }
}
