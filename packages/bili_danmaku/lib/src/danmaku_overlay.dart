import 'package:flutter/material.dart';

import 'danmaku_controller.dart';
import 'danmaku_frame_driver.dart';

/// One bounded frame driver repaints this layer when placements change.
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

final class _DanmakuOverlayState extends State<DanmakuOverlay> {
  late DanmakuFrameDriver<DanmakuPlacement> _driver;

  @override
  void initState() {
    super.initState();
    _driver = _createDriver();
  }

  DanmakuFrameDriver<DanmakuPlacement> _createDriver() {
    final controller = widget.controller;
    return DanmakuFrameDriver(
      controller: controller,
      readFrame: controller.frame,
      needsFrame: () => controller.needsFrame,
      nextFrameDelay: () => controller.nextFrameDelay,
      appearance: () => controller.textStyle,
      equivalent: (a, b) =>
          identical(a.event, b.event) && a.x == b.x && a.y == b.y,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _driver.setEnabled(TickerMode.valuesOf(context).enabled);
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _driver.dispose();
      _driver = _createDriver()
        ..setEnabled(TickerMode.valuesOf(context).enabled);
    }
  }

  @override
  void dispose() {
    _driver.dispose();
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
              _driver,
              MediaQuery.maybeDevicePixelRatioOf(context) ??
                  View.of(context).devicePixelRatio,
            ),
            size: Size.infinite,
          ),
        ),
      );
    },
  );
}

final class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter(this.controller, this.driver, this.pixelRatio)
    : super(repaint: driver);
  final DanmakuController controller;
  final DanmakuFrameDriver<DanmakuPlacement> driver;
  final double pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final placements = driver.frame;
    for (final placement in placements) {
      controller.paintText(
        placement.event,
        canvas,
        Offset(placement.x, placement.y),
        pixelRatio: pixelRatio,
      );
    }
  }

  @override
  bool shouldRepaint(_DanmakuPainter oldDelegate) =>
      !identical(controller, oldDelegate.controller) ||
      !identical(driver, oldDelegate.driver) ||
      pixelRatio != oldDelegate.pixelRatio;
}
