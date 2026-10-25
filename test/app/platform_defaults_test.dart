import 'package:bilisail/app/platform_defaults.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop and Android use their own player defaults', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(defaultDanmakuArea, platform == TargetPlatform.android ? .5 : .75);
      expect(defaultDanmakuFontScale, switch (platform) {
        TargetPlatform.android => .6,
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => .8,
        _ => 1.0,
      });
      expect(
        defaultPlayerControlsMode,
        [
              TargetPlatform.windows,
              TargetPlatform.macOS,
              TargetPlatform.linux,
            ].contains(platform)
            ? PlayerControlsMode.dynamic
            : PlayerControlsMode.click,
      );
    }
  });
  test('high energy defaults on only for Windows and macOS', () {
    for (final platform in TargetPlatform.values) {
      expect(
        highEnergyProgressEnabledForPlatform(platform),
        platform == TargetPlatform.windows || platform == TargetPlatform.macOS,
      );
    }
  });
  test(
    'workspace header is hidden on Android/iOS and visible on Windows/macOS',
    () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(workspaceHeaderVisibleForPlatform(platform), isFalse);
      }
      for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
        expect(workspaceHeaderVisibleForPlatform(platform), isTrue);
      }
    },
  );
  test('all platforms default to dual tabs', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        workspaceNavigationModeForPlatform(platform),
        WorkspaceNavigationMode.dualTabs,
      );
      expect(defaultWorkspaceNavigationMode, WorkspaceNavigationMode.dualTabs);
    }
  });
}
