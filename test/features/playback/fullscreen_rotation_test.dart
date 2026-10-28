import 'package:bilisail/core/platform/device_rotation.dart';
import 'package:bilisail/features/playback/domain/fullscreen_rotation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const portrait = DeviceRotation(DevicePosture.portrait, autoRotate: true);
  const landscape = DeviceRotation(DevicePosture.landscape, autoRotate: true);
  const unknown = DeviceRotation(DevicePosture.unknown, autoRotate: true);

  test('automatic entry needs physical landscape and a rotated viewport', () {
    final rotation = FullscreenRotation();
    expect(rotation.shouldEnter(viewportLandscape: true), isFalse);
    rotation.update(portrait);
    expect(rotation.shouldEnter(viewportLandscape: true), isFalse);
    rotation.update(landscape);
    expect(rotation.shouldEnter(viewportLandscape: false), isFalse);
    expect(rotation.shouldEnter(viewportLandscape: true), isTrue);
    rotation.update(unknown);
    expect(rotation.shouldEnter(viewportLandscape: true), isFalse);
  });

  test('system rotation lock blocks automatic but not explicit fullscreen', () {
    final rotation = FullscreenRotation();
    rotation.update(
      const DeviceRotation(DevicePosture.landscape, autoRotate: false),
    );
    expect(rotation.shouldEnter(viewportLandscape: true), isFalse);
    rotation.entered();
    rotation.update(
      const DeviceRotation(DevicePosture.portrait, autoRotate: false),
    );
    expect(rotation.shouldExit, isTrue);
  });

  test('manual portrait entry survives forced landscape metrics', () {
    final rotation = FullscreenRotation()
      ..update(portrait)
      ..entered();
    // The application may force a landscape viewport, but the device remains
    // physically upright until the user turns it sideways.
    rotation.update(portrait);
    expect(rotation.shouldExit, isFalse);
    rotation.update(unknown);
    expect(rotation.shouldExit, isFalse);
    rotation.update(landscape);
    expect(rotation.shouldExit, isFalse);
    rotation.update(portrait);
    expect(rotation.shouldExit, isTrue);
  });

  test(
    'automatic entry exits on physical portrait despite a locked viewport',
    () {
      final rotation = FullscreenRotation()
        ..update(landscape)
        ..entered();
      rotation.update(unknown);
      expect(rotation.shouldExit, isFalse);
      rotation.update(portrait);
      expect(rotation.shouldExit, isTrue);
      rotation.exited();
      expect(rotation.returnToPortrait, isFalse);
      expect(rotation.canReleasePortrait, isFalse);
    },
  );

  test(
    'explicit landscape exit waits in portrait, without automatic reentry',
    () {
      final rotation = FullscreenRotation()
        ..update(landscape)
        ..entered()
        ..exited();
      expect(rotation.returnToPortrait, isTrue);
      expect(rotation.shouldEnter(viewportLandscape: true), isFalse);
      rotation.update(unknown);
      expect(rotation.canReleasePortrait, isFalse);
      rotation.update(portrait);
      expect(rotation.canReleasePortrait, isTrue);
      rotation.returnToPortrait = false;
      rotation.update(landscape);
      expect(rotation.shouldEnter(viewportLandscape: true), isTrue);
    },
  );

  test('new manual entry replaces a pending portrait return', () {
    final rotation = FullscreenRotation()
      ..update(landscape)
      ..entered()
      ..exited();
    rotation.entered();
    expect(rotation.returnToPortrait, isFalse);
    rotation.update(portrait);
    expect(rotation.shouldExit, isTrue);
  });

  test('unsupported device never automatically enters', () {
    final rotation = FullscreenRotation();
    rotation.update(
      const DeviceRotation(
        DevicePosture.landscape,
        autoRotate: true,
        supported: false,
      ),
    );
    expect(rotation.shouldEnter(viewportLandscape: true), isFalse);
  });

  test(
    'suspending fullscreen clears stale posture but remembers the prior turn',
    () {
      final rotation = FullscreenRotation()
        ..update(landscape)
        ..entered();
      rotation.suspend();
      expect(rotation.rotation, isNull);
      expect(rotation.shouldExit, isFalse);
      rotation.update(portrait);
      expect(rotation.shouldExit, isTrue);
    },
  );

  test('reset drops a hidden page posture and pending restrictions', () {
    final rotation = FullscreenRotation()
      ..update(landscape)
      ..entered()
      ..exited();
    rotation.reset();
    expect(rotation.rotation, isNull);
    expect(rotation.returnToPortrait, isFalse);
    expect(rotation.shouldEnter(viewportLandscape: true), isFalse);
    rotation.update(portrait);
    expect(rotation.shouldExit, isFalse);
  });
}
