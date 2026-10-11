import 'package:bili_player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot equality includes every observable playback field', () {
    const snapshot = PlaybackSnapshot(
      phase: PlaybackPhase.playing,
      generation: 1,
      videoDimensions: VideoDimensions(1920, 1080),
    );
    final same = snapshot.copyWith(
      videoDimensions: const VideoDimensions(1920, 1080),
    );
    expect(same, snapshot);
    expect(same.hashCode, snapshot.hashCode);
    for (final changed in [
      snapshot.copyWith(phase: PlaybackPhase.paused),
      snapshot.copyWith(generation: 2),
      snapshot.copyWith(position: const Duration(microseconds: 1)),
      snapshot.copyWith(duration: const Duration(microseconds: 1)),
      snapshot.copyWith(buffered: const Duration(microseconds: 1)),
      snapshot.copyWith(desiredPlaying: true),
      snapshot.copyWith(isBuffering: true),
      snapshot.copyWith(isSeeking: true),
      snapshot.copyWith(rate: 2),
      snapshot.copyWith(volume: 50),
      snapshot.copyWith(videoDimensions: const VideoDimensions(1280, 720)),
      const PlaybackSnapshot(phase: PlaybackPhase.playing, generation: 1),
    ]) {
      expect(changed, isNot(snapshot));
    }
  });
}
