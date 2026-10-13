import 'package:flutter/material.dart';

import 'danmaku_frame_driver.dart';
import 'live_danmaku_controller.dart';

final class LiveDanmakuOverlay extends StatefulWidget {
  const LiveDanmakuOverlay({
    super.key,
    required this.controller,
    this.bottomInset = 64,
  });
  final LiveDanmakuController controller;
  final double bottomInset;
  @override
  State<LiveDanmakuOverlay> createState() => _LiveDanmakuOverlayState();
}

final class _LiveDanmakuOverlayState extends State<LiveDanmakuOverlay> {
  late DanmakuFrameDriver<LiveDanmakuPlacement> _driver;
  @override
  void initState() {
    super.initState();
    _driver = _createDriver();
  }

  DanmakuFrameDriver<LiveDanmakuPlacement> _createDriver() {
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
  void didUpdateWidget(covariant LiveDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
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
            painter: _LivePainter(
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

final class _LivePainter extends CustomPainter {
  _LivePainter(this.controller, this.driver, this.pixelRatio)
    : super(repaint: driver);
  final LiveDanmakuController controller;
  final DanmakuFrameDriver<LiveDanmakuPlacement> driver;
  final double pixelRatio;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final item in driver.frame) {
      controller.paintText(
        item.event,
        canvas,
        Offset(item.x, item.y),
        pixelRatio: pixelRatio,
      );
    }
  }

  @override
  bool shouldRepaint(_LivePainter oldDelegate) =>
      !identical(controller, oldDelegate.controller) ||
      !identical(driver, oldDelegate.driver) ||
      pixelRatio != oldDelegate.pixelRatio;
}
