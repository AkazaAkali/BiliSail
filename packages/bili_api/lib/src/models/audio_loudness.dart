/// Optional per-source loudness measurements returned by Web playurl.
final class ApiAudioLoudness {
  const ApiAudioLoudness({
    required this.measuredI,
    required this.normalTargetI,
    required this.highDynamicTargetI,
    required this.undersizedTargetI,
  });

  final double measuredI, normalTargetI, highDynamicTargetI, undersizedTargetI;

  static ApiAudioLoudness? parse(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final scenes = value['multi_scene_args'];
    if (scenes is! Map<String, Object?>) return null;
    double? number(Object? raw) {
      final n = raw is num
          ? raw.toDouble()
          : raw is String
          ? double.tryParse(raw)
          : null;
      // Positive sentinel values (including 0.001) are not measurements.
      return n != null && n.isFinite && n >= -70 && n < 0 ? n : null;
    }

    final measured = number(value['measured_i']);
    final normal = number(scenes['normal_target_i']);
    final high = number(scenes['high_dynamic_target_i']);
    final minimum = number(scenes['undersized_target_i']);
    if (measured == null ||
        normal == null ||
        high == null ||
        minimum == null ||
        minimum > high ||
        high > normal) {
      return null;
    }
    return ApiAudioLoudness(
      measuredI: measured,
      normalTargetI: normal,
      highDynamicTargetI: high,
      undersizedTargetI: minimum,
    );
  }
}
