import 'dart:math' as math;

import 'package:bili_player/bili_player.dart';

/// Only confirmed portrait media gets more space. Embedded black bars are part
/// of the source and are never inferred from pixels or cropped here.
double inlineVideoHeight({
  required double width,
  required double availableHeight,
  required bool portraitPhone,
  VideoDimensions? dimensions,
}) {
  final fallback = width * 9 / 16;
  if (!portraitPhone ||
      dimensions == null ||
      dimensions.width <= 0 ||
      dimensions.height <= dimensions.width ||
      !availableHeight.isFinite ||
      availableHeight <= 0) {
    return fallback;
  }
  // Keep information reachable below the player, without making a short
  // viewport's player even smaller than the existing landscape layout.
  final maximum = math.max(fallback, availableHeight * 0.65);
  return math.min(width * dimensions.height / dimensions.width, maximum);
}
