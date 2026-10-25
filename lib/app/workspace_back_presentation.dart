import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'workspace_tabs.dart';

/// The real destination UI participates in Back while media stays unselected.
class WorkspaceBackPresentation extends InheritedWidget {
  const WorkspaceBackPresentation({
    super.key,
    required this.progress,
    required this.edge,
    required this.source,
    required this.destination,
    required super.child,
  });
  final Animation<double> progress;
  final SwipeEdge edge;
  final WorkspaceTab? source, destination;

  static WorkspaceBackPresentation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceBackPresentation>();

  bool matches(WorkspaceTab? target, WorkspaceTab view) =>
      target?.id == view.id && target?.location.path == view.location.path;

  @override
  bool updateShouldNotify(WorkspaceBackPresentation oldWidget) =>
      progress != oldWidget.progress ||
      edge != oldWidget.edge ||
      source != oldWidget.source ||
      destination != oldWidget.destination;
}

class WorkspaceFrameTab extends InheritedWidget {
  const WorkspaceFrameTab({super.key, required this.tab, required super.child});
  final WorkspaceTab tab;
  static WorkspaceTab? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceFrameTab>()?.tab;
  @override
  bool updateShouldNotify(WorkspaceFrameTab oldWidget) => tab != oldWidget.tab;
}
