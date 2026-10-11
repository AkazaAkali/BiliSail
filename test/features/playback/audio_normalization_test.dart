import 'package:bilisail/domain/audio_normalization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AudioLoudness sample(double measured, {double normal = -14}) => AudioLoudness(
    measuredI: measured,
    normalTargetI: normal,
    highDynamicTargetI: -24,
    undersizedTargetI: -28,
  );
  test('server targets determine gain and quiet material is protected', () {
    final data = sample(-16.7);
    expect(data.gainDb(AudioNormalizationMode.standard), closeTo(2.7, 1e-9));
    expect(
      data.gainDb(AudioNormalizationMode.highDynamic),
      closeTo(-7.3, 1e-9),
    );
    expect(data.gainDb(AudioNormalizationMode.off), 0);
    expect(
      sample(-16.7, normal: -18).gainDb(AudioNormalizationMode.standard),
      closeTo(-1.3, 1e-9),
    );
    expect(sample(-28).gainDb(AudioNormalizationMode.standard), 14);
    expect(sample(-28.01).gainDb(AudioNormalizationMode.standard), 0);
  });
  test('invalid and placeholder measurements cannot amplify audio', () {
    for (final value in [double.nan, double.infinity, .001, 0.0, -100.0]) {
      for (final mode in AudioNormalizationMode.values) {
        expect(sample(value).gainDb(mode), 0);
      }
    }
    expect(
      sample(-16, normal: double.nan).gainDb(AudioNormalizationMode.standard),
      0,
    );
  });
}
