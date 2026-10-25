import 'package:flutter/widgets.dart';

/// Animates a new primary destination without replacing its retained tree.
class PrimaryNavigationTransition extends StatefulWidget {
  const PrimaryNavigationTransition({
    super.key,
    required this.index,
    required this.enabled,
    required this.child,
  });

  static const duration = Duration(milliseconds: 220);

  /// Null represents a detail page, outside primary navigation.
  final int? index;
  final bool enabled;
  final Widget child;

  @override
  State<PrimaryNavigationTransition> createState() =>
      _PrimaryNavigationTransitionState();
}

class _PrimaryNavigationTransitionState
    extends State<PrimaryNavigationTransition>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: PrimaryNavigationTransition.duration,
    value: 1,
  );
  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  double _direction = 1;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _controller.value = 1;
  }

  @override
  void didUpdateWidget(PrimaryNavigationTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.index;
    final next = widget.index;
    if (!widget.enabled || _reduceMotion || previous == null || next == null) {
      _controller.value = 1;
    } else if (oldWidget.enabled && previous != next) {
      _direction = next > previous ? 1 : -1;
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: SlideTransition(
      position: Tween(
        begin: Offset(0.04 * _direction, 0),
        end: Offset.zero,
      ).animate(_progress),
      textDirection: Directionality.of(context),
      // Keep dense image feeds opaque: fading the whole page adds an opacity
      // layer and blending during the same frames that restore the list.
      // Translation still updates compositing without rebuilding the pages.
      child: RepaintBoundary(child: widget.child),
    ),
  );

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }
}
