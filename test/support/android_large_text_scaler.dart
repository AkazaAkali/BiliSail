import 'package:flutter/painting.dart';

// Samples captured from Android API 36 at its 200% system font setting.
// Unlike linear scaling, large reference sizes stay unchanged.
final class AndroidLargeTextScaler extends TextScaler {
  const AndroidLargeTextScaler();

  static const _samples = [
    (0.0, 0.0),
    (12.0, 24.0),
    (14.0, 26.0),
    (15.0, 27.0),
    (16.0, 28.0),
    (20.0, 34.0),
    (24.0, 36.0),
    (36.0, 43.31428527832031),
    (140.0, 140.0),
  ];

  @override
  double scale(double fontSize) {
    for (var index = 1; index < _samples.length; index++) {
      final lower = _samples[index - 1];
      final upper = _samples[index];
      if (fontSize <= upper.$1) {
        final fraction = (fontSize - lower.$1) / (upper.$1 - lower.$1);
        return lower.$2 + (upper.$2 - lower.$2) * fraction;
      }
    }
    return fontSize;
  }

  @override
  double get textScaleFactor => 2;
}
