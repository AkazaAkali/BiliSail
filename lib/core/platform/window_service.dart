import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

enum FullScreenOrientation { portrait, landscape }

class WindowService {
  static const _textInputChannel = MethodChannel('bilisail/text_input');

  /// Keep IME composition attached only while a Flutter editor needs it.
  /// Otherwise Windows can consume punctuation before Flutter sees a key event.
  Future<void> setTextInputActive(bool active) async {
    if (!Platform.isWindows) return;
    await _textInputChannel.invokeMethod<void>('setActive', active);
  }

  bool get hasDesktopWindow =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// Other desktop platforms retain their native caption until validated.
  bool get hasCustomTitleBar => Platform.isWindows;
  bool _fullScreen = false;
  bool get isFullScreen => _fullScreen;

  Future<void> initialize() async {
    if (!hasDesktopWindow) return;
    await windowManager.ensureInitialized();
    await windowManager.setTitle('BiliSail');
    await windowManager.setMinimumSize(const Size(420, 560));
    if (hasCustomTitleBar) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
  }

  Future<void> setFullScreen(
    bool value, {
    FullScreenOrientation? orientation,
  }) async {
    if (hasDesktopWindow) {
      await windowManager.setFullScreen(value);
    } else {
      if (!value || orientation != null) {
        await SystemChrome.setPreferredOrientations(
          !value
              ? const []
              : switch (orientation) {
                  FullScreenOrientation.landscape => const [
                    DeviceOrientation.landscapeLeft,
                    DeviceOrientation.landscapeRight,
                  ],
                  _ => const [DeviceOrientation.portraitUp],
                },
        );
      }
      await SystemChrome.setEnabledSystemUIMode(
        value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
    _fullScreen = value;
  }
}
