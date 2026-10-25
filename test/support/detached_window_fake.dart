import 'dart:ui' as ui;

import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Creates real secondary render trees without asking the engine for a window.
class FakeDetachedWindowFactory {
  FakeDetachedWindowFactory(this.mainView, {this.size = const Size(1120, 760)});

  final ui.FlutterView mainView;
  final Size size;
  final windows = <FakeDetachedWindow>[];

  int get creationCount => windows.length;
  FakeDetachedWindow? get lastWindow => windows.lastOrNull;

  FakeDetachedWindow call({
    required String title,
    required VoidCallback onCloseRequested,
  }) {
    final window = FakeDetachedWindow(
      mainView: mainView,
      viewId: 100 + windows.length,
      size: size,
      title: title,
      onCloseRequested: onCloseRequested,
    );
    windows.add(window);
    return window;
  }
}

class FakeDetachedWindow extends DetachedPlaybackWindow {
  FakeDetachedWindow({
    required ui.FlutterView mainView,
    required int viewId,
    required Size size,
    required this.title,
    required this.onCloseRequested,
  }) : view = FakeSecondaryFlutterView(mainView, viewId: viewId, size: size),
       assert(viewId != mainView.viewId);

  final FakeSecondaryFlutterView view;
  final VoidCallback onCloseRequested;
  bool disposed = false;
  int activationCount = 0;
  String title;

  @override
  int get viewId => view.viewId;

  @override
  bool get isOpen => !disposed;

  @override
  late final windowService = WindowService.forView(
    viewId: viewId,
    setFullScreen: (_) async {},
    activate: () async => activate(),
  );

  void requestClose() => onCloseRequested();

  @override
  Widget buildView(Widget child) => View(view: view, child: child);

  @override
  void activate() => activationCount++;

  @override
  void setTitle(String title) => this.title = title;

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    super.dispose();
  }
}

// Additional views follow Flutter's BSD-licensed multi_view_testing.dart
// harness: each view owns a render tree without submitting it to the engine.
class FakeSecondaryFlutterView extends TestFlutterView {
  FakeSecondaryFlutterView(
    ui.FlutterView view, {
    required this.viewId,
    required Size size,
  }) : super(
         view: view,
         platformDispatcher: view.platformDispatcher as TestPlatformDispatcher,
         display: view.display as TestDisplay,
       ) {
    devicePixelRatio = 1;
    physicalSize = size;
  }

  @override
  final int viewId;

  @override
  void render(ui.Scene scene, {ui.Size? size}) {}

  @override
  void updateSemantics(ui.SemanticsUpdate update) {}
}
