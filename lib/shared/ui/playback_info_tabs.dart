import 'package:flutter/material.dart';

import 'paging_tab_strip.dart';
import 'compact_phone_spacing.dart';
import 'retained_tab_view.dart';

/// Shared sidebar navigation; the player stays outside the retained pager.
final class PlaybackInfoTabs extends StatefulWidget {
  const PlaybackInfoTabs({
    super.key,
    required this.labels,
    required this.value,
    required this.onChanged,
    required this.pageBuilder,
    required this.viewKey,
    this.itemKey,
    this.trailing,
    this.compact = false,
    this.compactPhoneNavigation = false,
    this.preloadPages = false,
    this.showNavigation = true,
  });

  final List<Widget> labels;
  final int value;
  final ValueChanged<int> onChanged;
  final RetainedTabPageBuilder<int> pageBuilder;
  final Key viewKey;
  final Key Function(int)? itemKey;
  final Widget? trailing;
  final bool compact;

  /// Video details can trim phone tab padding without changing label typography.
  final bool compactPhoneNavigation;
  final bool preloadPages;
  final bool showNavigation;

  @override
  State<PlaybackInfoTabs> createState() => _PlaybackInfoTabsState();
}

final class _PlaybackInfoTabsState extends State<PlaybackInfoTabs> {
  late final _progress = TabPagingProgress(widget.value.toDouble());

  @override
  Widget build(BuildContext context) {
    final tabs = List<int>.generate(widget.labels.length, (index) => index);
    final phoneNavigation =
        widget.compactPhoneNavigation && isCompactPhoneLayout(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showNavigation)
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: PagingTabStrip<int>(
                    tabs: tabs,
                    value: widget.value,
                    onSelected: widget.onChanged,
                    progress: _progress,
                    itemKey: widget.itemKey,
                    labelBuilder: (_, tab) => widget.labels[tab],
                    spacing: 0,
                    fullWidthIndicator: true,
                    indicatorHeight: widget.compact ? 2 : 3,
                    unselectedColor: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                    buttonStyle: TextButton.styleFrom(
                      padding: phoneNavigation
                          ? const EdgeInsets.symmetric(
                              horizontal: 17,
                              vertical: 8,
                            )
                          : widget.compact
                          ? const EdgeInsets.fromLTRB(16, 11, 16, 9)
                          : const EdgeInsets.fromLTRB(17, 15, 17, 12),
                      minimumSize: phoneNavigation
                          ? const Size(48, 48)
                          : Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: const RoundedRectangleBorder(),
                      textStyle: widget.compact
                          ? Theme.of(context).textTheme.labelLarge
                          : Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ),
              if (widget.trailing case final trailing?)
                phoneNavigation
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: trailing,
                      )
                    : trailing,
            ],
          ),
        if (widget.showNavigation) const Divider(height: 1),
        Expanded(
          key: const ValueKey('playback-info-pages'),
          child: RetainedTabView<int>(
            tabs: tabs,
            value: widget.value,
            onChanged: widget.onChanged,
            progress: _progress,
            viewKey: widget.viewKey,
            pageBuilder: widget.pageBuilder,
            preloadPages: widget.preloadPages,
            swipeEnabled: widget.showNavigation,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }
}
