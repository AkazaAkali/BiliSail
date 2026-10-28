import '../../../core/platform/device_rotation.dart';

/// Physical posture is never inferred from the viewport: manual fullscreen
/// forces the viewport sideways even while the phone is still held upright.
class FullscreenRotation {
  DeviceRotation? rotation;
  bool _landscapeSeen = false;
  bool returnToPortrait = false;

  void update(DeviceRotation value) {
    rotation = value;
    if (value.posture == DevicePosture.landscape) _landscapeSeen = true;
  }

  void entered() {
    returnToPortrait = false;
    _landscapeSeen = rotation?.posture == DevicePosture.landscape;
  }

  bool get shouldExit =>
      _landscapeSeen && rotation?.posture == DevicePosture.portrait;

  bool shouldEnter({required bool viewportLandscape}) =>
      !returnToPortrait &&
      rotation?.supported == true &&
      viewportLandscape &&
      rotation?.autoRotate == true &&
      rotation?.posture == DevicePosture.landscape;

  void exited() {
    // Explicit exit returns to portrait details, not landscape details. Release
    // this temporary restriction once the user physically brings the phone up.
    returnToPortrait = rotation?.posture == DevicePosture.landscape;
    _landscapeSeen = false;
  }

  bool get canReleasePortrait =>
      returnToPortrait && rotation?.posture == DevicePosture.portrait;

  void suspend() {
    rotation = null;
    returnToPortrait = false;
  }

  void reset() {
    rotation = null;
    _landscapeSeen = false;
    returnToPortrait = false;
  }
}
