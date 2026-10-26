import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/platform/window_brightness_service.dart';

/// Only the picture participates; buttons above this layer keep their gestures.
class PlayerSwipeControls extends StatefulWidget {
  const PlayerSwipeControls({
    super.key,
    required this.enabled,
    required this.sourceGeneration,
    required this.volume,
    required this.setVolume,
    required this.child,
    this.brightness,
  });

  final bool enabled;
  final int sourceGeneration;
  final double volume;
  final Future<void> Function(double) setVolume;
  final Widget child;
  final WindowBrightnessService? brightness;

  @override
  State<PlayerSwipeControls> createState() => _PlayerSwipeControlsState();
}

class _PlayerSwipeControlsState extends State<PlayerSwipeControls>
    with WidgetsBindingObserver {
  late final _brightnessService =
      widget.brightness ?? WindowBrightnessService();
  Object? _drag;
  bool _left = false;
  bool _foreground = true;
  bool _readingBrightness = false;
  bool _released = false;
  bool _writingBrightness = false;
  double? _pendingBrightness;
  double _brightness = 1;
  double _startValue = 0;
  double _delta = 0;
  double _height = 1;
  String? _feedback;
  Timer? _feedbackTimer;

  bool get _enabled => widget.enabled && _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) _cancel();
  }

  @override
  void didUpdateWidget(covariant PlayerSwipeControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceGeneration != widget.sourceGeneration ||
        oldWidget.enabled != widget.enabled) {
      _cancel();
      if (!widget.enabled) _resetBrightness();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _cancel();
      if (!_foreground) _resetBrightness();
    });
  }

  void _cancel() {
    _drag = null;
    _pendingBrightness = null;
    _feedback = null;
    _feedbackTimer?.cancel();
  }

  void _resetBrightness() {
    _pendingBrightness = null;
    _brightness = 1;
    if (_brightnessService.isNative) {
      unawaited(
        _brightnessService.reset().catchError((Object _) {
          // Android also restores the window override when the engine detaches.
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel();
    _resetBrightness();
    super.dispose();
  }

  void _start(DragStartDetails details, Size size) {
    if (!_enabled || ModalRoute.of(context)?.isCurrent == false) return;
    _feedbackTimer?.cancel();
    final drag = Object();
    _drag = drag;
    _released = false;
    _left = details.localPosition.dx < size.width / 2;
    _height = size.height;
    _delta = 0;
    _startValue = _left ? _brightness : widget.volume / 100;
    _readingBrightness = _left && _brightnessService.isNative;
    if (_readingBrightness) unawaited(_readBrightness(drag));
  }

  Future<void> _readBrightness(Object drag) async {
    try {
      final value = await _brightnessService.read();
      if (!mounted ||
          !identical(_drag, drag) ||
          !_enabled ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      _startValue = value;
      _readingBrightness = false;
      _apply();
      if (_released) {
        _drag = null;
        _hideFeedback();
      }
    } catch (_) {
      if (mounted && identical(_drag, drag)) {
        setState(() {
          _drag = null;
          _feedback = '亮度调节失败';
        });
        _hideFeedback();
      }
    }
  }

  void _update(DragUpdateDetails details) {
    if (_drag == null || !_enabled) return;
    if (ModalRoute.of(context)?.isCurrent == false) {
      setState(_cancel);
      return;
    }
    _delta -= details.delta.dy / _height;
    if (!_readingBrightness) _apply();
  }

  void _apply() {
    final value = (_startValue + _delta).clamp(_left ? .01 : 0.0, 1.0);
    setState(() {
      _feedback = '${_left ? '亮度' : '音量'} ${(value * 100).round()}%';
      if (_left) _brightness = value;
    });
    if (_left) {
      if (_brightnessService.isNative) {
        _pendingBrightness = value;
        unawaited(_writeBrightness());
      }
    } else {
      final drag = _drag;
      unawaited(
        widget.setVolume(value * 100).catchError((Object _) {
          if (mounted && identical(_drag, drag)) {
            setState(() => _feedback = '音量调节失败');
          }
        }),
      );
    }
  }

  Future<void> _writeBrightness() async {
    if (_writingBrightness) return;
    _writingBrightness = true;
    try {
      while (_pendingBrightness != null) {
        final value = _pendingBrightness;
        _pendingBrightness = null;
        if (value != null) await _brightnessService.set(value);
      }
    } catch (_) {
      _pendingBrightness = null;
      if (mounted && _enabled) {
        setState(() => _feedback = '亮度调节失败');
      }
    } finally {
      _writingBrightness = false;
    }
  }

  void _end() {
    if (_drag == null) return;
    _released = true;
    if (!_readingBrightness) {
      _drag = null;
      _hideFeedback();
    }
  }

  void _cancelGesture() {
    if (_drag == null) return;
    _drag = null;
    _hideFeedback();
  }

  void _hideFeedback() {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Listener(
      onPointerCancel: (_) => _cancelGesture(),
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        gestures: {
          if (_enabled)
            VerticalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  VerticalDragGestureRecognizer
                >(
                  () =>
                      VerticalDragGestureRecognizer(
                          supportedDevices: {PointerDeviceKind.touch},
                        )
                        ..dragStartBehavior = DragStartBehavior.down
                        ..onlyAcceptDragOnThreshold = true,
                  (recognizer) {
                    recognizer.onStart = (details) =>
                        _start(details, constraints.biggest);
                    recognizer.onUpdate = _update;
                    recognizer.onEnd = (_) => _end();
                    recognizer.onCancel = _cancelGesture;
                  },
                ),
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (!_brightnessService.isNative && _brightness < 1)
              IgnorePointer(
                child: ColoredBox(
                  key: const ValueKey('player-brightness-dimmer'),
                  color: Colors.black.withValues(alpha: 1 - _brightness),
                ),
              ),
            if (_feedback case final feedback?)
              Center(
                child: IgnorePointer(
                  child: Semantics(
                    liveRegion: true,
                    child: Container(
                      key: const ValueKey('player-swipe-feedback'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        feedback,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
