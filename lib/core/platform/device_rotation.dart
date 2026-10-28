/// Physical device posture, independent of an application orientation lock.
enum DevicePosture { unknown, portrait, landscape }

class DeviceRotation {
  const DeviceRotation(
    this.posture, {
    required this.autoRotate,
    this.supported = true,
  });

  final DevicePosture posture;
  final bool autoRotate;
  final bool supported;
}
