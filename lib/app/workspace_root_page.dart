import 'package:flutter/widgets.dart';

import '../core/presentation/workspace_activity.dart';

enum WorkspaceRootSection {
  feed('/'),
  account('/me'),
  messages('/messages'),
  downloads('/downloads'),
  settings('/settings');

  const WorkspaceRootSection(this.path);
  final String path;

  static WorkspaceRootSection fromLocation(Uri location) => values.firstWhere(
    (section) => section.path == location.path,
    orElse: () => feed,
  );
}

typedef WorkspaceRootBuilder = Widget Function(
  BuildContext context,
  Uri location,
);

/// Primary navigation changes selection while each visited root keeps its tree.
class WorkspaceRootPage extends StatefulWidget {
  const WorkspaceRootPage({
    super.key,
    required this.location,
    required this.feedBuilder,
    required this.accountBuilder,
    required this.messagesBuilder,
    required this.downloadsBuilder,
    required this.settingsBuilder,
  });

  final Uri location;
  final WorkspaceRootBuilder feedBuilder;
  final WidgetBuilder accountBuilder;
  final WorkspaceRootBuilder messagesBuilder;
  final WorkspaceRootBuilder downloadsBuilder;
  final WorkspaceRootBuilder settingsBuilder;

  @override
  State<WorkspaceRootPage> createState() => _WorkspaceRootPageState();
}

class _WorkspaceRootPageState extends State<WorkspaceRootPage> {
  final _locations = <WorkspaceRootSection, Uri>{};
  final _storage = <WorkspaceRootSection, PageStorageBucket>{};

  WorkspaceRootSection get _selected =>
      WorkspaceRootSection.fromLocation(widget.location);

  @override
  void initState() {
    super.initState();
    _rememberLocation();
  }

  @override
  void didUpdateWidget(WorkspaceRootPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rememberLocation();
  }

  void _rememberLocation() {
    _locations[_selected] = widget.location;
    _storage.putIfAbsent(_selected, PageStorageBucket.new);
  }

  Widget _buildRoot(
    BuildContext context,
    WorkspaceRootSection section,
    Uri location,
  ) => switch (section) {
    WorkspaceRootSection.feed => widget.feedBuilder(context, location),
    WorkspaceRootSection.account => widget.accountBuilder(context),
    WorkspaceRootSection.messages => widget.messagesBuilder(context, location),
    WorkspaceRootSection.downloads => widget.downloadsBuilder(
      context,
      location,
    ),
    WorkspaceRootSection.settings => widget.settingsBuilder(context, location),
  };

  Widget _retained({
    required Key key,
    required bool selected,
    required PageStorageBucket storage,
    required Widget child,
  }) => Offstage(
    key: key,
    offstage: !selected,
    child: ExcludeFocus(
      excluding: !selected,
      child: WorkspaceActivity(
        active: selected && WorkspaceActivity.isActive(context),
        child: PageStorage(bucket: storage, child: child),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (final section in WorkspaceRootSection.values)
        if (_locations[section] case final location?)
          _retained(
            key: ValueKey('workspace-root-${section.name}'),
            selected: _selected == section,
            storage: _storage.putIfAbsent(section, PageStorageBucket.new),
            child: Builder(
              builder: (context) => _buildRoot(context, section, location),
            ),
          ),
    ],
  );
}
