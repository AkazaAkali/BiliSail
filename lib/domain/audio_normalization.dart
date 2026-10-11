enum AudioNormalizationMode { standard, highDynamic, off }

extension AudioNormalizationLabel on AudioNormalizationMode {
  String get label => switch (this) {
    AudioNormalizationMode.standard => '标准',
    AudioNormalizationMode.highDynamic => '高动态',
    AudioNormalizationMode.off => '关闭',
  };
}

/// Integrated loudness and server-selected targets, in LUFS.
final class AudioLoudness {
  const AudioLoudness({
    required this.measuredI,
    required this.normalTargetI,
    required this.highDynamicTargetI,
    required this.undersizedTargetI,
  });

  final double measuredI, normalTargetI, highDynamicTargetI, undersizedTargetI;

  double gainDb(AudioNormalizationMode mode) {
    if (mode == AudioNormalizationMode.off ||
        [
          measuredI,
          normalTargetI,
          highDynamicTargetI,
          undersizedTargetI,
        ].any((v) => !v.isFinite || v < -70 || v >= 0) ||
        undersizedTargetI > highDynamicTargetI ||
        highDynamicTargetI > normalTargetI ||
        measuredI < undersizedTargetI) {
      return 0;
    }
    final target = mode == AudioNormalizationMode.standard
        ? normalTargetI
        : highDynamicTargetI;
    final gain = target - measuredI;
    // Reject implausible amplification rather than magnifying invalid metadata.
    return gain >= -60 && gain <= 30 ? gain : 0;
  }
}
