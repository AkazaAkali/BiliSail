import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/workspace_playback_window.dart';
import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/detached_window_fake.dart';
import '../support/input_test_app.dart';

void main() {
  for (final (key, button) in [
    ('MouseBack', kBackMouseButton),
    ('MouseForward', kForwardMouseButton),
  ]) {
    testWidgets(
      '$key closes playback without returning the browser on window handoff',
      (tester) async {
        final harness = _Harness(tester, key);
        addTearDown(harness.router.dispose);
        await harness.mount();
        final window = harness.windows.lastWindow!;

        harness.buttons = button;
        harness.pointer(
          PointerDownEvent(
            viewId: window.viewId,
            pointer: 1,
            kind: PointerDeviceKind.mouse,
            buttons: button,
          ),
        );
        await tester.pumpAndSettle();
        harness.buttons = 0;
        harness.pointer(
          PointerUpEvent(
            viewId: window.disposed ? tester.view.viewId : window.viewId,
            pointer: window.disposed ? 2 : 1,
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pumpAndSettle();

        expect(window.disposed, isTrue);
        expect(harness.activations, 1);
        expect(
          harness.router.routeInformationProvider.value.uri.path,
          '/user/42',
        );
        expect(find.text('/user/42'), findsOneWidget);

        // A separate click in the browser still performs its own Back.
        harness.pointer(
          PointerDownEvent(
            viewId: tester.view.viewId,
            pointer: 3,
            kind: PointerDeviceKind.mouse,
            buttons: button,
          ),
        );
        harness.pointer(
          PointerUpEvent(
            viewId: tester.view.viewId,
            pointer: 3,
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pumpAndSettle();
        expect(harness.router.routeInformationProvider.value.uri.path, '/');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets('playback side-button cancellation does not navigate', (
    tester,
  ) async {
    final harness = _Harness(tester, 'MouseBack');
    addTearDown(harness.router.dispose);
    await harness.mount();
    final window = harness.windows.lastWindow!;
    harness.pointer(
      PointerDownEvent(
        viewId: window.viewId,
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      ),
    );
    await tester.pumpAndSettle();
    expect(window.disposed, isFalse);
    harness.pointer(
      PointerCancelEvent(
        viewId: window.viewId,
        pointer: 1,
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(window.disposed, isFalse);
    expect(harness.activations, 0);

    // Keyboard close keeps its press-time behavior.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();
    expect(window.disposed, isTrue);
    expect(harness.router.routeInformationProvider.value.uri.path, '/user/42');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('playback side-button release after refocus does not navigate', (
    tester,
  ) async {
    final harness = _Harness(tester, 'MouseBack');
    addTearDown(harness.router.dispose);
    await harness.mount();
    final window = harness.windows.lastWindow!;
    harness.pointer(
      PointerDownEvent(
        viewId: window.viewId,
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      ),
    );
    harness.focus(tester.view.viewId);
    await tester.pumpAndSettle();
    harness.focus(window.viewId);
    await tester.pumpAndSettle();
    harness.pointer(
      PointerUpEvent(
        viewId: window.viewId,
        pointer: 1,
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(window.disposed, isFalse);
    expect(harness.activations, 0);
    expect(find.text('/user/42'), findsOneWidget);
    expect(find.text('/video/BV1234567890'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

class _Harness {
  _Harness(this.tester, String key)
    : windows = FakeDetachedWindowFactory(tester.view),
      shortcuts = const ShortcutSettings.defaults().withKeys(
        ShortcutAction.closeTab,
        ['Ctrl+W', key],
      );

  final WidgetTester tester;
  final FakeDetachedWindowFactory windows;
  final ShortcutSettings shortcuts;
  int buttons = 0;
  int activations = 0;

  void pointer(PointerEvent event) => tester.binding.handlePointerEvent(event);

  void focus(int viewId) => tester.binding.handleViewFocusChanged(
    ViewFocusEvent(
      viewId: viewId,
      state: ViewFocusState.focused,
      direction: ViewFocusDirection.undefined,
    ),
  );

  void activateBrowser() {
    activations++;
    focus(tester.view.viewId);
    // Model the pinned Windows embedder: entering a view while a button is
    // held starts a Down in that view. Defer delivery until the current event
    // has finished, as native window messages do.
    final pressed = buttons;
    Future<void>.microtask(() {
      if (pressed != 0) {
        pointer(
          PointerCancelEvent(
            viewId: windows.lastWindow!.viewId,
            pointer: 1,
            kind: PointerDeviceKind.mouse,
          ),
        );
      }
      pointer(
        PointerRemovedEvent(
          viewId: windows.lastWindow!.viewId,
          kind: PointerDeviceKind.mouse,
        ),
      );
      pointer(
        PointerAddedEvent(
          viewId: tester.view.viewId,
          kind: PointerDeviceKind.mouse,
        ),
      );
      if (pressed != 0) {
        pointer(
          PointerDownEvent(
            viewId: tester.view.viewId,
            pointer: 2,
            kind: PointerDeviceKind.mouse,
            buttons: pressed,
          ),
        );
      }
    });
  }

  late final router = GoRouter(
    routes: [
      ShellRoute(
        observers: [],
        builder: (context, state, child) => BiliAppShell(
          location: state.uri.toString(),
          navigationMode: WorkspaceNavigationMode.dualTabs,
          shortcuts: shortcuts,
          onActivateBrowser: activateBrowser,
          pageBuilder: (_, tab) => Center(child: Text(tab.location.path)),
          playbackWindowBuilder:
              (
                context, {
                required child,
                required playback,
                required activationToken,
                required onClose,
                required onBack,
                required onHome,
                required onError,
              }) => DesktopPlaybackWindow(
                windowFactory: windows.call,
                activationToken: activationToken,
                onCloseRequested: onClose,
                onError: onError,
                playback: playback == null
                    ? null
                    : WorkspacePlaybackWindow(
                        theme: ThemeData(),
                        shortcuts: shortcuts,
                        onBack: onBack,
                        onHome: onHome,
                        onClose: onClose,
                        onActivateBrowser: activateBrowser,
                        child: playback,
                      ),
                child: child,
              ),
          child: child,
        ),
        routes: [
          for (final path in ['/', '/user/:id', '/video/:id'])
            GoRoute(path: path, builder: (_, _) => const SizedBox()),
        ],
      ),
    ],
  );

  Future<void> mount() async {
    await tester.pumpWidget(
      InputTestApp.router(routerConfig: router, shortcuts: shortcuts),
    );
    await tester.pumpAndSettle();
    router.go('/user/42');
    await tester.pumpAndSettle();
    router.go('/video/BV1234567890');
    await tester.pumpAndSettle();
    focus(windows.lastWindow!.viewId);
    await tester.pumpAndSettle();
  }
}
