import 'package:flutter/foundation.dart';

import '../features/settings/domain/app_settings.dart';

/// Platform defaults apply only when no valid user preference has been saved.
WorkspaceNavigationMode workspaceNavigationModeForPlatform(
  TargetPlatform platform,
) => platform == TargetPlatform.android
    ? WorkspaceNavigationMode.singlePage
    : WorkspaceNavigationMode.multipleTabs;

WorkspaceNavigationMode get defaultWorkspaceNavigationMode =>
    workspaceNavigationModeForPlatform(defaultTargetPlatform);

/// Mobile navigation uses system back without desktop workspace chrome.
bool workspaceHeaderVisibleForPlatform(TargetPlatform platform) =>
    platform != TargetPlatform.android && platform != TargetPlatform.iOS;

bool get workspaceHeaderVisible =>
    workspaceHeaderVisibleForPlatform(defaultTargetPlatform);

bool highEnergyProgressEnabledForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.windows || platform == TargetPlatform.macOS;

bool get defaultHighEnergyProgressEnabled =>
    highEnergyProgressEnabledForPlatform(defaultTargetPlatform);

double danmakuAreaForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.android ? .5 : .75;

double get defaultDanmakuArea => danmakuAreaForPlatform(defaultTargetPlatform);

double danmakuFontScaleForPlatform(TargetPlatform platform) =>
    platform == TargetPlatform.android ? .6 : 1.0;

double get defaultDanmakuFontScale =>
    danmakuFontScaleForPlatform(defaultTargetPlatform);
