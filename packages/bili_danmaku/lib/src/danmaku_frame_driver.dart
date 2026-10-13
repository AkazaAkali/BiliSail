import 'dart:async';

import 'package:flutter/foundation.dart';

/// Only request a Flutter frame when the displayed placements change. A Ticker
/// also schedules unchanged frames at the monitor refresh rate, causing the
/// video texture and entire window to be composited at e.g. 180Hz on Windows.
/// Positions still come from the controller's clock, never accumulated ticks.
final class DanmakuFrameDriver<T> extends ChangeNotifier {
  DanmakuFrameDriver({
    required this.controller,
    required this.readFrame,
    required this.needsFrame,
    required this.nextFrameDelay,
    required this.appearance,
    required this.equivalent,
  }) {
    controller.addListener(_changed);
    _update();
  }

  // Native Dart timers truncate sub-millisecond durations. 16.667ms becomes
  // 16ms (62.5Hz) on Windows; round up to keep the animation below 60Hz.
  static const frameInterval = Duration(milliseconds: 17);
  final Listenable controller;
  final List<T> Function() readFrame;
  final bool Function() needsFrame;
  final Duration? Function() nextFrameDelay;
  final Object Function() appearance;
  final bool Function(T, T) equivalent;
  List<T> _frame = const [];
  List<T> get frame => _frame;
  Object? _appearance;
  Timer? _animation;
  Timer? _wake;
  bool _enabled = true;

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (enabled) {
      _update();
    } else {
      _cancel();
    }
  }

  void _changed() {
    if (!_enabled) return;
    // Coalesce confirmations/bursts into the already pending animation frame.
    // Pause and other idle transitions refresh immediately and cancel timers.
    if (_animation != null && needsFrame()) return;
    _update();
  }

  void _update() {
    if (!_enabled) return;
    _wake?.cancel();
    _wake = null;
    final next = readFrame();
    final style = appearance();
    var changed = style != _appearance || next.length != _frame.length;
    if (!changed) {
      for (var i = 0; i < next.length; i++) {
        if (!equivalent(next[i], _frame[i])) {
          changed = true;
          break;
        }
      }
    }
    final hadContent = _frame.isNotEmpty;
    _frame = next;
    _appearance = style;
    if (changed && (hadContent || next.isNotEmpty)) notifyListeners();
    if (needsFrame()) {
      _animation ??= Timer.periodic(frameInterval, (_) => _update());
    } else {
      _animation?.cancel();
      _animation = null;
      final delay = nextFrameDelay();
      if (delay != null) _wake = Timer(delay, _update);
    }
  }

  void _cancel() {
    _animation?.cancel();
    _animation = null;
    _wake?.cancel();
    _wake = null;
  }

  @override
  void dispose() {
    _cancel();
    controller.removeListener(_changed);
    super.dispose();
  }
}
