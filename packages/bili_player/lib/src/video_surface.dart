import 'package:flutter/widgets.dart';

import 'player_contract.dart';

/// Keeps presentation independent of the native player and its controller.
final class VideoSurface extends StatefulWidget {
  const VideoSurface({super.key, required this.engine, this.paintScale = 1})
    : assert(paintScale > 0 && paintScale < double.infinity);
  final PlayerEngine engine;

  /// Maximum ancestor paint scale, which layout constraints do not include.
  /// Reserve these pixels so a scaled surface does not magnify a small texture.
  final double paintScale;

  @override
  State<VideoSurface> createState() => _VideoSurfaceState();
}

final class _VideoSurfaceState extends State<VideoSurface> {
  final Object _owner = Object();
  int _layoutRevision = 0;
  ({double width, double height, double dpr})? _lastLayout;

  VideoViewportSource? get _viewport => widget.engine is VideoViewportSource
      ? widget.engine as VideoViewportSource
      : null;

  @override
  void initState() {
    super.initState();
    _viewport?.attachVideoViewport(_owner);
  }

  @override
  void didUpdateWidget(VideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.engine, widget.engine)) {
      if (oldWidget.engine is VideoViewportSource) {
        (oldWidget.engine as VideoViewportSource).detachVideoViewport(_owner);
      }
      _layoutRevision++;
      _lastLayout = null;
      _viewport?.attachVideoViewport(_owner);
    }
  }

  @override
  void dispose() {
    _layoutRevision++;
    _viewport?.detachVideoViewport(_owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = _viewport;
      final width = constraints.maxWidth * widget.paintScale;
      final height = constraints.maxHeight * widget.paintScale;
      if (viewport != null &&
          width.isFinite &&
          height.isFinite &&
          width > 0 &&
          height > 0) {
        final dpr = View.of(context).devicePixelRatio;
        final layout = (width: width, height: height, dpr: dpr);
        if (layout != _lastLayout) {
          _lastLayout = layout;
          final revision = ++_layoutRevision;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || revision != _layoutRevision) return;
            viewport.updateVideoViewport(
              _owner,
              logicalWidth: width,
              logicalHeight: height,
              devicePixelRatio: dpr,
            );
          });
        }
      }
      return widget.engine is VideoSurfaceSource
          ? (widget.engine as VideoSurfaceSource).buildVideoSurface()
          : const ColoredBox(color: Color(0xFF000000));
    },
  );
}
