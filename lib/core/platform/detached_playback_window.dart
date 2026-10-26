// The application pins Flutter 3.47.6. Keep its experimental windowing API
// behind this adapter so an SDK update has one explicit compatibility boundary.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/src/foundation/_features.dart' as flutter_features;
import 'package:flutter/src/widgets/_window.dart' as flutter_window;
import 'package:flutter/src/widgets/_window_macos.dart' as flutter_macos;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../presentation/window_input_focus.dart';
import 'window_service.dart';

typedef DetachedPlaybackWindowFactory = DetachedPlaybackWindow Function({
  required String title,
  required VoidCallback onCloseRequested,
});

abstract class DetachedPlaybackWindow extends ChangeNotifier {
  static bool _windowingReady = false;
  static bool _macOSWindowingReady = false;

  static Future<void> prepareMacOSWindowing() async {
    _macOSWindowingReady = false;
    final ready = await const MethodChannel('bilisail/application_window')
        .invokeMethod<bool>('prepareWindowing')
        .timeout(const Duration(seconds: 5));
    if (ready != true) {
      throw UnsupportedError(
        'macOS engine already has an implicit controller.',
      );
    }
    _macOSWindowingReady = true;
  }

  // Flutter 3.47.6's macOS create-window entry point calls enableMultiView,
  // which NSAsserts if an implicit view controller is already attached. That
  // Objective-C exception aborts the process across FFI; Dart cannot catch it.
  // The engine can expose a dummy Dart view 0 even without a native controller,
  // so only the native bootstrap can confirm that this transition is safe.
  static bool get isSupported => switch (defaultTargetPlatform) {
    TargetPlatform.windows => true,
    TargetPlatform.macOS => _macOSWindowingReady,
    _ => false,
  };

  static DetachedPlaybackWindow create({
    required String title,
    required VoidCallback onCloseRequested,
    Size size = const Size(1120, 760),
    BoxConstraints constraints = const BoxConstraints(
      minWidth: 420,
      minHeight: 360,
    ),
  }) {
    if (!Platform.isWindows && !Platform.isMacOS) {
      throw UnsupportedError('Detached playback requires Windows or macOS.');
    }
    if (!isSupported) {
      throw UnsupportedError(
        'Detached playback is incompatible with the current engine views.',
      );
    }
    // The pinned stable SDK includes the complete implementation but its tool
    // only exposes the flag on main, and rejects the reserved dart-define.
    // Do not change the user's SDK channel or global Flutter configuration.
    if (!_windowingReady) {
      flutter_features.isWindowingEnabled = true;
      // Binding initialization predates opening playback and cached an
      // unsupported owner while the experimental feature was still disabled.
      WidgetsBinding.instance.windowingOwner = flutter_window
          .createDefaultWindowingOwner();
      _windowingReady = true;
    }
    return _FlutterDetachedPlaybackWindow(
      title: title,
      onCloseRequested: onCloseRequested,
      size: size,
      constraints: constraints,
    );
  }

  int get viewId;
  bool get isOpen;
  WindowService get windowService;
  Widget buildView(Widget child);
  void activate();
  void setTitle(String title);
  Future<void> prepare() async {}
  Future<void> saveGeometry() async {}
}

class DesktopPlaybackWindow extends StatefulWidget {
  const DesktopPlaybackWindow({
    super.key,
    required this.child,
    required this.playback,
    required this.onCloseRequested,
    required this.onError,
    this.activationToken,
    this.title = 'BiliSail 播放',
    this.windowFactory,
  });

  final Widget child;
  final Widget? playback;
  final VoidCallback onCloseRequested;
  final void Function(Object error) onError;
  final Object? activationToken;
  final String title;
  final DetachedPlaybackWindowFactory? windowFactory;

  @override
  State<DesktopPlaybackWindow> createState() => _DesktopPlaybackWindowState();
}

class _DesktopPlaybackWindowState extends State<DesktopPlaybackWindow> {
  final _playbackKey = GlobalKey();
  DetachedPlaybackWindow? _window;
  bool _closeRequested = false;
  Object? _pendingWindowUpdate;
  Timer? _windowUpdateTimer;
  bool _createRequested = false;
  bool _activateRequested = false;
  bool _titleRequested = false;
  Object? _opening;

  @override
  void initState() {
    super.initState();
    if (widget.playback != null) _scheduleWindowUpdate(create: true);
  }

  void _scheduleWindowUpdate({
    bool create = false,
    bool activate = false,
    bool title = false,
  }) {
    _createRequested |= create;
    _activateRequested |= activate;
    _titleRequested |= title;
    if (_pendingWindowUpdate != null) return;
    final request = Object();
    _pendingWindowUpdate = request;
    // Native window operations can pump messages and reenter Flutter frame
    // callbacks. Leave the entire frame stack before entering the embedder.
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (!mounted || !identical(_pendingWindowUpdate, request)) return;
      _windowUpdateTimer = Timer(Duration.zero, () {
        _windowUpdateTimer = null;
        if (!mounted || !identical(_pendingWindowUpdate, request)) return;
        _pendingWindowUpdate = null;
        final create = _createRequested;
        final activate = _activateRequested;
        final title = _titleRequested;
        _createRequested = false;
        _activateRequested = false;
        _titleRequested = false;
        if (widget.playback == null || _closeRequested) return;
        if (_window == null && create) {
          unawaited(_open());
          return;
        }
        final window = _window;
        if (window == null || !window.isOpen) return;
        if (title) window.setTitle(widget.title);
        if (activate) window.activate();
      });
      binding.ensureVisualUpdate();
    });
    binding.ensureVisualUpdate();
  }

  void _afterFrame(VoidCallback callback) {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      Timer.run(callback);
      // Keep settling callers moving until the queued event gets its turn.
      binding.ensureVisualUpdate();
    });
    binding.ensureVisualUpdate();
  }

  void _cancelWindowUpdate() {
    _windowUpdateTimer?.cancel();
    _windowUpdateTimer = null;
    _pendingWindowUpdate = null;
    _createRequested = false;
    _activateRequested = false;
    _titleRequested = false;
    _opening = null;
  }

  Future<void> _open() async {
    final request = Object();
    _opening = request;
    DetachedPlaybackWindow? created;
    final initialTitle = widget.title;
    final initialActivation = widget.activationToken;
    try {
      final factory = widget.windowFactory ?? DetachedPlaybackWindow.create;
      final window = factory(
        title: widget.title,
        onCloseRequested: () {
          if (identical(_opening, request) ||
              (created != null && identical(_window, created))) {
            _requestClose();
          }
        },
      );
      created = window;
      if (!mounted ||
          !identical(_opening, request) ||
          widget.playback == null ||
          _closeRequested) {
        _disposeAfterFrame(window);
        return;
      }
      await window.prepare().timeout(const Duration(seconds: 2));
      // Channel completion may run among frame microtasks. Native title/focus
      // operations must leave that frame's stack just like initial creation.
      await Future<void>.delayed(Duration.zero);
      // Window creation can synchronously pump a close/navigation message.
      if (!mounted ||
          !identical(_opening, request) ||
          widget.playback == null ||
          _closeRequested) {
        _disposeAfterFrame(window);
        return;
      }
      if (!window.isOpen) {
        throw StateError('Playback window closed before it was ready.');
      }
      if (widget.title != initialTitle) window.setTitle(widget.title);
      if (!mounted ||
          !identical(_opening, request) ||
          widget.playback == null ||
          _closeRequested) {
        _disposeAfterFrame(window);
        return;
      }
      if (!window.isOpen) {
        throw StateError('Playback window closed while updating its title.');
      }
      if (widget.activationToken != initialActivation) window.activate();
      if (!mounted ||
          !identical(_opening, request) ||
          widget.playback == null ||
          _closeRequested) {
        _disposeAfterFrame(window);
        return;
      }
      if (!window.isOpen) {
        throw StateError('Playback window closed while activating.');
      }
      window.addListener(_windowChanged);
      setState(() {
        _window = window;
        _closeRequested = false;
      });
      _opening = null;
      // Adding a native view can consume the old view's pending engine frame.
      // The scheduler still considers that frame scheduled, so scheduleFrame
      // and scheduleForcedFrame would both return without waking the new view.
      WidgetsBinding.instance.platformDispatcher.scheduleFrame();
    } catch (error) {
      if (created != null) _disposeAfterFrame(created);
      if (mounted && identical(_opening, request)) {
        _opening = null;
        widget.onError(error);
      }
    }
  }

  void _disposeAfterFrame(DetachedPlaybackWindow window) {
    // Start the capture now, before a rapid new open queues its restore. Native
    // geometry is owner checked, so late capture/retire cannot change that view.
    final saved = window
        .saveGeometry()
        .timeout(const Duration(seconds: 2))
        .catchError((Object error, StackTrace stack) {
          if (error is PlatformException &&
              error.code == 'window_unavailable') {
            return;
          }
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'BiliSail playback window geometry',
            ),
          );
        });
    _afterFrame(() {
      unawaited(saved.whenComplete(() => Timer.run(window.dispose)));
    });
  }

  void _requestClose() {
    if (!mounted || _closeRequested) return;
    _closeRequested = true;
    widget.onCloseRequested();
  }

  void _windowChanged() {
    final window = _window;
    if (!mounted || window == null || window.isOpen) return;
    setState(_retireWindow);
    _requestClose();
  }

  void _retireWindow() {
    final window = _window;
    if (window == null) return;
    _window = null;
    window.removeListener(_windowChanged);
    // A Flutter view must leave the widget tree before its native view dies.
    // The native destroy path can reenter frame callbacks too.
    // Even an externally destroyed view may be notifying listeners right now.
    // Delay notifier disposal until that stack, and the render frame, unwind.
    _disposeAfterFrame(window);
  }

  @override
  void didUpdateWidget(DesktopPlaybackWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playback == null) {
      _closeRequested = false;
      _cancelWindowUpdate();
      _retireWindow();
      return;
    }
    // Coalesce media/title changes into the native window already preparing.
    // _open applies the latest widget values after checking its request lease.
    if (_window == null && _opening != null) return;
    if (oldWidget.playback == null ||
        (_window == null &&
            oldWidget.activationToken != widget.activationToken)) {
      _scheduleWindowUpdate(create: true);
    }
    final window = _window;
    if (window == null || !window.isOpen) return;
    if (oldWidget.title != widget.title ||
        oldWidget.activationToken != widget.activationToken) {
      _scheduleWindowUpdate(
        title: oldWidget.title != widget.title,
        activate: oldWidget.activationToken != widget.activationToken,
      );
    }
  }

  @override
  void dispose() {
    _cancelWindowUpdate();
    _retireWindow();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = _window;
    final playback = widget.playback;
    final content = playback == null
        ? null
        : KeyedSubtree(key: _playbackKey, child: playback);
    final windowReady = window != null && window.isOpen;
    return ViewAnchor(
      view: windowReady && content != null
          ? window.buildView(
              WindowServiceScope(service: window.windowService, child: content),
            )
          : null,
      child: Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.passthrough,
        children: [
          widget.child,
          // Mode changes move retained GlobalKey pages into this host in the
          // current frame. Keep them mounted while native creation is pending,
          // then reparent the same subtree into the new view on the next frame.
          if (!windowReady && content != null)
            Offstage(child: ExcludeFocus(child: content)),
        ],
      ),
    );
  }
}

class _FlutterDetachedPlaybackWindow extends DetachedPlaybackWindow {
  _FlutterDetachedPlaybackWindow({
    required String title,
    required VoidCallback onCloseRequested,
    required Size size,
    required BoxConstraints constraints,
  }) {
    _controller = flutter_window.RegularWindowController(
      size: size,
      constraints: constraints,
      title: title,
      delegate: _PlaybackWindowDelegate(
        onCloseRequested: onCloseRequested,
        onDestroyed: _destroyed,
      ),
    );
    windowService = WindowService.forView(
      viewId: viewId,
      nativeWindowHandle: _nativeWindowHandle,
      isAvailable: () => _open,
      setFullScreen: (value) async => _controller.setFullscreen(value),
      activate: () => WindowService.activateDesktopView(
        viewId,
        windowHandle: _nativeWindowHandle,
      ),
    );
    _controller.addListener(_rememberPresentation);
    _rememberPresentation();
  }

  void _rememberPresentation() {
    if (!_open) return;
    windowService.updateWindowPresentation(
      maximized: _controller.isMaximized,
      minimized: _controller.isMinimized,
      fullScreen: _controller.isFullscreen,
    );
  }

  late final flutter_window.RegularWindowController _controller;
  bool _open = true;
  bool _disposed = false;

  @override
  late final WindowService windowService;

  @override
  int get viewId => _controller.rootView.viewId;

  int? get _nativeWindowHandle => Platform.isMacOS
      ? flutter_macos.WindowingOwnerMacOS.getWindowHandle(_controller.rootView)
            .address
      : null;

  @override
  bool get isOpen => _open;

  @override
  Future<void> prepare() async {
    await windowService.configurePlaybackTitleBar();
    await windowService.restorePlaybackGeometry();
    await WindowInputFocus.instance.synchronizeNativeFocusIfSupported();
  }

  @override
  Future<void> saveGeometry() => windowService.savePlaybackGeometry();

  @override
  Widget buildView(Widget child) =>
      flutter_window.RegularWindow(controller: _controller, child: child);

  @override
  void activate() {
    if (!_open) return;
    // The pinned Win32 controller uses SW_RESTORE unconditionally. Native
    // activation restores only minimized windows and preserves zoom/geometry.
    unawaited(
      windowService.activate().catchError((Object error, StackTrace stack) {
        if (!_open) return;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'BiliSail desktop window',
          ),
        );
      }),
    );
  }

  @override
  void setTitle(String title) {
    if (_open) _controller.setTitle(title);
  }

  void _destroyed() {
    if (!_open) return;
    _open = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.removeListener(_rememberPresentation);
    if (_open) {
      _open = false;
      _controller.destroy();
    }
    _controller.dispose();
    super.dispose();
  }
}

class _PlaybackWindowDelegate
    with flutter_window.RegularWindowControllerDelegate {
  _PlaybackWindowDelegate({
    required this.onCloseRequested,
    required this.onDestroyed,
  });

  final VoidCallback onCloseRequested;
  final VoidCallback onDestroyed;

  @override
  void onWindowCloseRequested(
    flutter_window.RegularWindowController controller,
  ) => onCloseRequested();

  @override
  void onWindowDestroyed() => onDestroyed();
}
