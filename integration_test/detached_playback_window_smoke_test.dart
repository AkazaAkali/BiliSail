import 'dart:io';
import 'dart:ffi';
import 'dart:ui' show PlatformDispatcher;

import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/native_playback_window.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('implicit main view can add and retire one playback view', (
    tester,
  ) async {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    final implicit = PlatformDispatcher.instance.implicitView!;
    final baseline = PlatformDispatcher.instance.views.length;
    final errors = <Object>[];
    var closeRequests = 0;
    await WindowService().initialize();
    WindowService? playbackService;
    Widget build({required bool open}) => DesktopPlaybackWindow(
      onCloseRequested: () => closeRequests++,
      onError: errors.add,
      playback: !open
          ? null
          : MaterialApp(
              home: Builder(
                builder: (context) {
                  playbackService = WindowServiceScope.maybeOf(context);
                  return const Scaffold(body: Text('Detached playback probe'));
                },
              ),
            ),
      child: const MaterialApp(
        home: Scaffold(body: Text('Main browser probe')),
      ),
    );

    await tester.pumpWidget(build(open: true));
    await tester.pumpAndSettle();
    expect(errors, isEmpty);
    expect(PlatformDispatcher.instance.implicitView, same(implicit));
    expect(PlatformDispatcher.instance.views.length, baseline + 1);
    expect(playbackService, isNotNull);
    expect(playbackService!.viewId, isNot(implicit.viewId));
    final backOwner = Object();
    var backs = 0;
    await playbackService!.bindTitleBarBack(
      owner: backOwner,
      onBack: () => backs++,
    );
    if (Platform.isWindows) {
      final native = NativePlaybackWindow(playbackService!.viewId!);
      native.resize(1000, 700);
      await tester.pump(const Duration(milliseconds: 150));
      final userSize = native.outerSize;
      await playbackService!.activate();
      await tester.pump(const Duration(milliseconds: 150));
      expect(native.outerSize, userSize);
      native.maximize();
      await tester.pump(const Duration(milliseconds: 150));
      await playbackService!.activate();
      await tester.pump(const Duration(milliseconds: 150));
      expect(native.isMaximized, isTrue);
      native.minimize();
      await tester.pump(const Duration(milliseconds: 100));
      await playbackService!.activate();
      await tester.pump(const Duration(milliseconds: 150));
      expect(native.isMinimized, isFalse);
      expect(native.isMaximized, isTrue);
      native.doubleBack();
      await tester.pumpAndSettle();
      expect(backs, 1);
      final handle = _windowHandle(
        PlatformDispatcher.instance.engineId!,
        playbackService!.viewId!,
      );
      final heap = _getProcessHeap();
      final frame = _heapAlloc(heap, 8, sizeOf<_Rect>()).cast<_Rect>();
      final client = _heapAlloc(heap, 8, sizeOf<_Rect>()).cast<_Rect>();
      try {
        expect(_getWindowRect(handle, frame), isNot(0));
        expect(_getClientRect(handle, client), isNot(0));
        final decorations =
            frame.ref.bottom - frame.ref.top - client.ref.bottom;
        expect(decorations, greaterThanOrEqualTo(24 * _getDpi(handle) / 96));
      } finally {
        _heapFree(heap, 0, frame.cast());
        _heapFree(heap, 0, client.cast());
      }
    }
    await playbackService!.setTextInputActive(false);
    await playbackService!.setTextInputActive(true);
    await playbackService!.setFullScreen(true);
    await tester.pumpAndSettle();
    await playbackService!.setFullScreen(false);
    await tester.pumpAndSettle();
    await playbackService!.unbindTitleBarBack(backOwner);
    if (Platform.isWindows) {
      final handle = _windowHandle(
        PlatformDispatcher.instance.engineId!,
        playbackService!.viewId!,
      );
      _postMessage(handle, 0x0010, 0, 0);
      await tester.pumpAndSettle();
      expect(closeRequests, 1);
      expect(PlatformDispatcher.instance.views.length, baseline + 1);
    }

    await tester.pumpWidget(build(open: false));
    await tester.pumpAndSettle();
    expect(PlatformDispatcher.instance.views.length, baseline);
    expect(find.text('Main browser probe'), findsOneWidget);
    debugPrint(
      'NATIVE_WINDOW: shared engine captionBack/resize/maximize/fullscreen/IME/close passed',
    );
  });
}

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

@Native<Pointer<Void> Function(Int64, Int64)>(
  symbol: 'InternalFlutterWindows_WindowManager_GetTopLevelWindowHandle',
)
external Pointer<Void> _windowHandle(int engineId, int viewId);

@Native<Int32 Function(Pointer<Void>, Pointer<_Rect>)>(symbol: 'GetWindowRect')
external int _getWindowRect(Pointer<Void> window, Pointer<_Rect> rect);

@Native<Int32 Function(Pointer<Void>, Pointer<_Rect>)>(symbol: 'GetClientRect')
external int _getClientRect(Pointer<Void> window, Pointer<_Rect> rect);

@Native<Uint32 Function(Pointer<Void>)>(symbol: 'GetDpiForWindow')
external int _getDpi(Pointer<Void> window);

@Native<Int32 Function(Pointer<Void>, Uint32, IntPtr, IntPtr)>(
  symbol: 'PostMessageW',
)
external int _postMessage(
  Pointer<Void> window,
  int message,
  int wparam,
  int lparam,
);

@Native<Pointer<Void> Function()>(symbol: 'GetProcessHeap')
external Pointer<Void> _getProcessHeap();

@Native<Pointer<Void> Function(Pointer<Void>, Uint32, UintPtr)>(
  symbol: 'HeapAlloc',
)
external Pointer<Void> _heapAlloc(Pointer<Void> heap, int flags, int bytes);

@Native<Int32 Function(Pointer<Void>, Uint32, Pointer<Void>)>(
  symbol: 'HeapFree',
)
external int _heapFree(Pointer<Void> heap, int flags, Pointer<Void> memory);
