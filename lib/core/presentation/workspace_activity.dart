import 'package:flutter/widgets.dart';

/// Visibility and playback ownership are independent of page lifetime.
class WorkspaceActivity extends InheritedWidget {
  const WorkspaceActivity({
    super.key,
    required this.active,
    this.previewing = false,
    required super.child,
  });

  final bool active;
  final bool previewing;

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceActivity>()?.active ??
      true;

  /// A visible Back preview can load and lay out UI without owning media/input.
  static bool isVisible(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<WorkspaceActivity>();
    return scope == null || scope.active || scope.previewing;
  }

  @override
  bool updateShouldNotify(WorkspaceActivity oldWidget) =>
      active != oldWidget.active || previewing != oldWidget.previewing;
}

/// Historical page UI must not construct a native player before Back commits.
class WorkspaceMediaPermission extends InheritedWidget {
  const WorkspaceMediaPermission({
    super.key,
    required this.allowed,
    required super.child,
  });
  final bool allowed;
  static bool isAllowed(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WorkspaceMediaPermission>()
          ?.allowed ??
      true;
  @override
  bool updateShouldNotify(WorkspaceMediaPermission oldWidget) =>
      allowed != oldWidget.allowed;
}
