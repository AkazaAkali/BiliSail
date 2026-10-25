import 'package:flutter/material.dart';

import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/retained_tab_view.dart';
import '../domain/home_channel.dart';

typedef HomeChannelPageBuilder = RetainedTabPageBuilder<HomeChannel>;

/// Each primary destination owns an isolated pager and retains visited pages.
final class HomeChannelSwipe extends StatefulWidget {
  const HomeChannelSwipe({
    super.key,
    required this.channel,
    required this.onChanged,
    required this.pageBuilder,
    this.animateSelection,
    this.channelGroups,
  });

  final HomeChannel channel;
  final ValueChanged<HomeChannel> onChanged;
  final HomeChannelPageBuilder pageBuilder;
  final TabSelectionAnimation<HomeChannel>? animateSelection;
  final List<List<HomeChannel>>? channelGroups;

  @override
  State<HomeChannelSwipe> createState() => _HomeChannelSwipeState();
}

final class _HomeChannelSwipeState extends State<HomeChannelSwipe> {
  final _selections = <HomeChannel, HomeChannel>{};
  final _progress = <HomeChannel, TabPagingProgress>{};

  @override
  Widget build(BuildContext context) {
    final selected = widget.channel == HomeChannel.ranking
        ? HomeChannel.popular
        : widget.channel;
    final groups = widget.channelGroups ?? [HomeChannel.primaryValues];
    final selectedGroup = groups.firstWhere(
      (group) => group.contains(selected),
    );
    _selections[selectedGroup.first] = selected;
    final sharedProgress = TabPagingScope.maybeOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final group in groups)
          if (_selections[group.first] case final previous?)
            Offstage(
              key: ValueKey(('home-channel-group', group.first)),
              offstage: group.first != selectedGroup.first,
              child: WorkspaceActivity(
                active:
                    group.first == selectedGroup.first &&
                    WorkspaceActivity.isActive(context),
                previewing:
                    group.first == selectedGroup.first &&
                    WorkspaceActivity.isVisible(context) &&
                    !WorkspaceActivity.isActive(context),
                child: RetainedTabView<HomeChannel>(
                  tabs: group,
                  value: group.contains(previous) ? previous : group.first,
                  progress:
                      group.first == selectedGroup.first &&
                          sharedProgress != null
                      ? sharedProgress
                      : _progress.putIfAbsent(
                          group.first,
                          () => TabPagingProgress(0),
                        ),
                  onChanged: (channel) {
                    if (group.first == selectedGroup.first &&
                        WorkspaceActivity.isActive(context)) {
                      widget.onChanged(channel);
                    }
                  },
                  animateSelection: widget.animateSelection,
                  pageBuilder: widget.pageBuilder,
                  viewKey: const ValueKey('home-channel-swipe'),
                ),
              ),
            ),
      ],
    );
  }

  @override
  void dispose() {
    for (final progress in _progress.values) {
      progress.dispose();
    }
    super.dispose();
  }
}
