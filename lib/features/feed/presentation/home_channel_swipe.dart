import 'package:flutter/material.dart';

import '../../../shared/ui/retained_tab_view.dart';
import '../domain/home_channel.dart';

typedef HomeChannelPageBuilder = RetainedTabPageBuilder<HomeChannel>;

/// Native tab paging keeps the outgoing and incoming pages on screen together.
final class HomeChannelSwipe extends StatelessWidget {
  const HomeChannelSwipe({
    super.key,
    required this.channel,
    required this.onChanged,
    required this.pageBuilder,
    this.animateSelection,
  });

  final HomeChannel channel;
  final ValueChanged<HomeChannel> onChanged;
  final HomeChannelPageBuilder pageBuilder;
  final TabSelectionAnimation<HomeChannel>? animateSelection;

  @override
  Widget build(BuildContext context) => RetainedTabView<HomeChannel>(
    tabs: HomeChannel.primaryValues,
    value: channel == HomeChannel.ranking ? HomeChannel.popular : channel,
    onChanged: onChanged,
    animateSelection: animateSelection,
    pageBuilder: pageBuilder,
    viewKey: const ValueKey('home-channel-swipe'),
  );
}
