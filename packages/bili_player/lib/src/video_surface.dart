import 'package:flutter/widgets.dart';

import 'player_contract.dart';
import 'video_composition.dart';
import 'video_output.dart';

/// Keeps presentation independent of the native player and its controller.
final class VideoSurface extends StatefulWidget {
  const VideoSurface({super.key, required this.engine, this.paintScale = 1})
    : output = null,
      assert(paintScale > 0 && paintScale < double.infinity);

  const VideoSurface.output({
    super.key,
    required VideoOutput this.output,
    this.paintScale = 1,
  }) : engine = null,
       assert(paintScale > 0 && paintScale < double.infinity);

  final PlayerEngine? engine;
  final VideoOutput? output;

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
  VideoOutput? _output;

  static VideoOutput? _resolve(VideoSurface widget) {
    if (widget.output case final output?) return output;
    if (widget.engine case VideoOutputSource source) return source.videoOutput;
    return null;
  }

  @override
  void initState() {
    super.initState();
    _output = _resolve(widget);
    _output?.attach(_owner);
  }

  @override
  void didUpdateWidget(VideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final output = _resolve(widget);
    if (!identical(_output, output)) {
      _output?.detach(_owner);
      _output = output;
      _layoutRevision++;
      _lastLayout = null;
      _output?.attach(_owner);
    }
  }

  @override
  void dispose() {
    _layoutRevision++;
    _output?.detach(_owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final output = _output;
      final width = constraints.maxWidth * widget.paintScale;
      final height = constraints.maxHeight * widget.paintScale;
      if (output != null &&
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
            output.updateViewport(
              _owner,
              logicalWidth: width,
              logicalHeight: height,
              devicePixelRatio: dpr,
            );
          });
        }
      }
      return output == null
          ? const ColoredBox(color: Color(0xFF000000))
          : VideoCompositionScope.of(context)
                .buildVideoSurface(context, output);
    },
  );
}
