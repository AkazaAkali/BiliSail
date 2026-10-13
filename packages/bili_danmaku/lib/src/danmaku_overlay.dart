import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'danmaku_controller.dart';

/// A single ticker repaints only this layer; no per-comment animation widgets.
final class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.controller,
    this.bottomInset = 0,
  });
  final DanmakuController controller;
  final double bottomInset;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

final class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  Timer? _arrivalWake;
  bool _paintedContent = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (widget.controller.needsFrame) {
        _repaint.value++;
      } else {
        _ticker.stop();
        _scheduleArrival();
      }
    });
    widget.controller.addListener(_onControllerChanged);
    _onControllerChanged();
  }

  void _onControllerChanged() {
    _arrivalWake?.cancel();
    if (widget.controller.needsFrame) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
    }
    // Clock confirmations can retime the one-shot arrival without repainting
    // an empty layer. Keep the clearing frame after visible content is removed.
    if (widget.controller.needsFrame ||
        widget.controller.visibleCount > 0 ||
        _paintedContent) {
      _repaint.value++;
    }
    _scheduleArrival();
  }

  void _scheduleArrival() {
    _arrivalWake?.cancel();
    final delay = widget.controller.nextFrameDelay;
    if (delay != null) {
      _arrivalWake = Timer(delay, () {
        if (mounted) _onControllerChanged();
      });
    }
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _onControllerChanged();
    }
  }

  @override
  void dispose() {
    _arrivalWake?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth.isFinite && constraints.maxHeight.isFinite) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.controller.setViewport(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              bottomInset: widget.bottomInset,
            );
          }
        });
      }
      return IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _DanmakuPainter(
              widget.controller,
              _repaint,
              MediaQuery.maybeDevicePixelRatioOf(context) ??
                  View.of(context).devicePixelRatio,
              (visible) => _paintedContent = visible,
            ),
            size: Size.infinite,
          ),
        ),
      );
    },
  );
}

final class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter(
    this.controller,
    Listenable repaint,
    this.pixelRatio,
    this.onPainted,
  ) : super(repaint: repaint);
  final DanmakuController controller;
  final double pixelRatio;
  final void Function(bool visible) onPainted;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final placements = controller.frame();
    for (final placement in placements) {
      controller.paintText(
        placement.event,
        canvas,
        Offset(placement.x, placement.y),
        pixelRatio: pixelRatio,
      );
    }
    onPainted(placements.isNotEmpty);
  }

  @override
  bool shouldRepaint(_DanmakuPainter oldDelegate) =>
      !identical(controller, oldDelegate.controller) ||
      pixelRatio != oldDelegate.pixelRatio;
}
