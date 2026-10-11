import 'package:bilisail/features/playback/application/playback_startup_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'stage samples retain only bounded timing metadata and propagate errors',
    () async {
      var now = Duration.zero;
      final diagnostics = PlaybackStartupDiagnostics(now: () => now);
      for (var generation = 0; generation < 40; generation++) {
        expect(
          await diagnostics.measure(
            generation,
            PlaybackStartupStage.resolve,
            () async {
              now += const Duration(milliseconds: 4);
              return generation;
            },
          ),
          generation,
        );
      }
      expect(
        diagnostics.samples,
        hasLength(PlaybackStartupDiagnostics.capacity),
      );
      expect(diagnostics.samples.first.generation, 8);
      expect(diagnostics.samples.last.elapsed, const Duration(milliseconds: 4));
      final error = StateError('sensitive source error');
      await expectLater(
        diagnostics.measure<void>(
          40,
          PlaybackStartupStage.nativeOpen,
          () async => throw error,
        ),
        throwsA(same(error)),
      );
      expect(diagnostics.samples.last.completed, isFalse);
      expect(diagnostics.samples.last.generation, 40);
      expect(
        diagnostics.samples,
        hasLength(PlaybackStartupDiagnostics.capacity),
      );
    },
  );
}
