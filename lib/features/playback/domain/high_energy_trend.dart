import 'dart:math' as math;

import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

final class HighEnergyPoint {
  const HighEnergyPoint(this.fraction, this.intensity);
  final double fraction, intensity;
}

final class HighEnergyTrend {
  HighEnergyTrend({
    required this.step,
    required this.span,
    required List<HighEnergyPoint> points,
  }) : points = List.unmodifiable(points);
  final Duration step, span;
  final List<HighEnergyPoint> points;

  /// Reject curves aggregated across multiple parts instead of stretching them.
  bool matchesDuration(Duration duration) =>
      duration > Duration.zero &&
      (duration.inMilliseconds - span.inMilliseconds).abs() <=
          math.max(2000, step.inMilliseconds * 2);
}

/// Optional metadata capability; does not participate in opening media.
abstract interface class HighEnergyRepository {
  Future<HighEnergyTrend?> highEnergy(
    VideoDetail video,
    VideoPart part, {
    required RequestCancellation cancellation,
  });
}
