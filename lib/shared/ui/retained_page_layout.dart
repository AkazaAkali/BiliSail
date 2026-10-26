import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps an offstage page at its last visible constraints until it is shown.
///
/// Place inside Offstage, never around a visible/interactive hidden page. Shared
/// toolbars can then change height without resizing every retained viewport.
/// Dirty descendants still lay out (including account/provider changes); only
/// unrelated parent constraints are isolated. Activation, including a Back
/// preview, always uses current constraints so resizing never paints stale UI.
final class RetainedPageLayout extends SingleChildRenderObjectWidget {
  const RetainedPageLayout({
    super.key,
    required this.visible,
    required super.child,
  });

  final bool visible;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRetainedPageLayout(visible);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderRetainedPageLayout).visible = visible;
  }
}

final class _RenderRetainedPageLayout extends RenderProxyBox {
  _RenderRetainedPageLayout(this._visible);

  bool _visible;
  BoxConstraints? _visibleConstraints;

  set visible(bool value) {
    if (value == _visible) return;
    _visible = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    if (_visible || _visibleConstraints == null) {
      _visibleConstraints = constraints;
    }
    final content = child;
    if (content == null) {
      size = constraints.smallest;
      return;
    }
    content.layout(_visibleConstraints!, parentUsesSize: true);
    size = constraints.constrain(content.size);
  }
}
