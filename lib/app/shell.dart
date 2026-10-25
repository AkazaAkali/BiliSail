import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../features/feed/domain/home_channel.dart';
import '../features/search/presentation/search_category_bar.dart';
import '../core/presentation/workspace_activity.dart';
import '../core/presentation/page_back_scope.dart';
import 'workspace_tabs.dart';
import 'workspace_navigation.dart';
import 'platform_defaults.dart';
import '../core/input/input_stroke.dart';
import '../core/input/shortcut_dispatcher.dart';
import '../core/presentation/input_scope.dart';
import 'shortcut_coordinator.dart';
import '../domain/shortcut_command.dart';
import '../features/settings/domain/shortcut_settings.dart';
import '../features/settings/domain/settings_category.dart';
import '../features/settings/domain/app_settings.dart';
import '../shared/ui/smooth_scroll_behavior.dart';
import '../shared/ui/bili_icons.dart';
import '../shared/ui/app_notice.dart';
import '../shared/ui/app_dialog.dart';
import '../shared/ui/paging_tab_strip.dart';
import '../shared/ui/page_tab_style.dart';
import '../shared/ui/retained_tab_view.dart';

typedef WorkspacePageBuilder = Widget Function(
  BuildContext context,
  WorkspaceTab tab,
);
typedef DragRegionBuilder = Widget Function(BuildContext context, Widget child);
typedef WorkspaceWindowBuilder = Widget Function(
  BuildContext context, {
  required Widget child,
  required Widget? playback,
  required Object? activationToken,
  required VoidCallback onClose,
  required VoidCallback onBack,
  required ValueChanged<Object> onError,
});

/// A visible browser must not take playback ownership from its sibling window.
class WorkspacePlaybackSelection extends InheritedWidget {
  const WorkspacePlaybackSelection({
    super.key,
    required this.tabId,
    required super.child,
  });
  final String? tabId;
  static String? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WorkspacePlaybackSelection>()
      ?.tabId;
  @override
  bool updateShouldNotify(WorkspacePlaybackSelection oldWidget) =>
      oldWidget.tabId != tabId;
}

/// Navigation within an existing playback page preserves the selected tab.
final class WorkspacePageNavigation extends InheritedWidget {
  const WorkspacePageNavigation({
    super.key,
    required this.navigate,
    required super.child,
  });

  final ValueChanged<Uri> navigate;

  static WorkspacePageNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspacePageNavigation>();

  @override
  bool updateShouldNotify(WorkspacePageNavigation oldWidget) =>
      navigate != oldWidget.navigate;
}

/// Builds shell navigation inside a page's own provider scope.
final class WorkspacePageHeader extends InheritedWidget {
  const WorkspacePageHeader({
    super.key,
    required this.builder,
    required super.child,
  });

  final WidgetBuilder builder;

  static Widget wrap(BuildContext context, Widget page) {
    final header = context
        .dependOnInheritedWidgetOfExactType<WorkspacePageHeader>();
    return header == null
        ? page
        : Column(
            children: [
              header.builder(context),
              Expanded(child: page),
            ],
          );
  }

  @override
  bool updateShouldNotify(WorkspacePageHeader oldWidget) =>
      builder != oldWidget.builder;
}

final class BiliAppShell extends StatefulWidget {
  const BiliAppShell({
    super.key,
    required this.location,
    required this.child,
    this.accountBuilder,
    this.pageBuilder,
    this.windowControlsBuilder,
    this.dragRegionBuilder,
    this.shortcuts = const ShortcutSettings.defaults(),
    this.navigationMode,
    this.accountIdentity,
    this.playbackWindowBuilder,
    this.onActivateBrowser,
  });
  final ShortcutSettings shortcuts;
  final WorkspaceNavigationMode? navigationMode;
  final Object? accountIdentity;
  final WorkspaceWindowBuilder? playbackWindowBuilder;
  final VoidCallback? onActivateBrowser;
  final String location;
  final Widget child;
  final WidgetBuilder? accountBuilder;
  final WorkspacePageBuilder? pageBuilder;
  final WidgetBuilder? windowControlsBuilder;
  final DragRegionBuilder? dragRegionBuilder;
  @override
  State<BiliAppShell> createState() => _BiliAppShellState();
}

final class _BiliAppShellState extends State<BiliAppShell>
    with WidgetsBindingObserver {
  static const _bottomNavigationHeight = 52.0;
  static const _bottomNavigationIconSize = 16.0;
  static const _bottomNavigationLabelStyle = TextStyle(
    fontSize: 11,
    height: 1.2,
  );

  final _workspace = WorkspaceTabs();
  final _searchController = TextEditingController();
  final _tabKeys = <String, GlobalKey>{};
  final _pageKeys = <String, GlobalKey>{};
  final _searchDrafts = <String, String>{};
  final _pageStorage = <String, PageStorageBucket>{};
  final _pageBack = <String, PageBackController>{};
  final _pagingProgress = <(String, bool), TabPagingProgress>{};
  final _lastChannels = <WorkspaceSection, HomeChannel>{};
  final _lastSections = <HomeChannel, String>{};
  SettingsCategory _lastSettingsCategory = SettingsCategory.appearance;
  bool _windowFailed = false;
  int _windowActivation = 0;
  bool _exitConfirmationOpen = false;

  bool get _android => Theme.of(context).platform == TargetPlatform.android;
  bool get _canReturnFromMessages =>
      _android && _workspace.canReturnFromMessages;

  bool get _desktopDual =>
      _dualTabs && widget.playbackWindowBuilder != null && !_windowFailed;
  WorkspaceTab get _displayTab => _desktopDual
      ? _workspace.tabs.firstWhere((tab) => tab.id == _workspace.browseId)
      : _workspace.active;

  PageBackController _backFor(String id) => _pageBack.putIfAbsent(
    id,
    () => PageBackController()..addListener(_pageBackChanged),
  );

  void _pageBackChanged() {
    if (mounted) setState(() {});
  }

  bool get _canGoBack =>
      (_pageBack[_displayTab.id]?.canGoBack ?? false) ||
      _canReturnFromMessages ||
      (_desktopDual ? _workspace.canGoBackBrowsing : _workspace.canGoBack);

  bool get _showBackButton =>
      _dualTabs &&
      _canGoBack &&
      (!(_displayTab.pinned && _displayTab.isRoot) ||
          _canReturnFromMessages ||
          (_pageBack[_displayTab.id]?.canGoBack ?? false));

  bool _goBackWithinPage() => _pageBack[_displayTab.id]?.goBack() ?? false;

  TabPagingProgress _pagingFor(WorkspaceTab tab) {
    final settings = tab.location.path == '/settings';
    final index = settings
        ? SettingsCategory.fromName(tab.location.queryParameters['section'])
              .index
        : HomeChannel.primaryValues
              .indexWhere(
                (channel) =>
                    channel.name ==
                    (tab.location.queryParameters['channel'] == 'ranking'
                        ? 'popular'
                        : tab.location.queryParameters['channel'] ??
                              'recommended'),
              )
              .clamp(0, HomeChannel.primaryValues.length - 1);
    return _pagingProgress.putIfAbsent((
      tab.id,
      settings,
    ), () => TabPagingProgress(index.toDouble()));
  }

  bool get _dualTabs =>
      (widget.navigationMode ?? defaultWorkspaceNavigationMode) ==
      WorkspaceNavigationMode.dualTabs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workspace.setDualMode(_dualTabs);
    _workspace.acceptRoute(Uri.parse(widget.location));
    _rememberSection(_displayTab.location);
    _restoreSearch();
    _searchController.addListener(_saveSearch);
  }

  @override
  void didUpdateWidget(covariant BiliAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.accountIdentity != oldWidget.accountIdentity) {
      _workspace.clearPlaybackHistory();
    }
    if (widget.navigationMode != oldWidget.navigationMode) {
      _windowFailed = false;
    }
    _workspace.setDualMode(_dualTabs);
    if (widget.navigationMode != oldWidget.navigationMode) _revealActiveTab();
    if (widget.location != oldWidget.location) {
      if (!_workspace.acceptRoute(Uri.parse(widget.location))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showAppNotice(context, '最多打开 16 个标签页，请先关闭不用的标签');
          context.go(_workspace.active.route.toString());
        });
        return;
      }
      _prunePages();
      _rememberSection(_displayTab.location);
      _restoreSearch();
      _revealActiveTab();
      if (_workspace.active.isPlayback) _windowActivation++;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _revealActiveTab();
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (!_desktopDual ||
        event.state != ViewFocusState.focused ||
        event.viewId != View.maybeOf(context)?.viewId ||
        _workspace.activeId == _workspace.browseId) {
      return;
    }
    // The browser remains visible while playback owns another view. Restore
    // its route on refocus so opening the same video is a new navigation and
    // raises the existing playback window, including clicks through the OS.
    _selectTab(_workspace.browseId);
  }

  void _prunePages() {
    final liveIds = _workspace.tabs.map((tab) => tab.id).toSet();
    _tabKeys.removeWhere((id, _) => !liveIds.contains(id));
    _pageKeys.removeWhere((id, _) => !liveIds.contains(id));
    _searchDrafts.removeWhere((id, _) => !liveIds.contains(id));
    _pageStorage.removeWhere((id, _) => !liveIds.contains(id));
    _pageBack.removeWhere((id, controller) {
      if (liveIds.contains(id)) return false;
      controller.dispose();
      return true;
    });
    _pagingProgress.removeWhere((key, progress) {
      if (liveIds.contains(key.$1)) return false;
      progress.dispose();
      return true;
    });
  }

  void _saveSearch() => _searchDrafts[_displayTab.id] = _searchController.text;
  void _restoreSearch() {
    _searchController.text =
        _searchDrafts[_displayTab.id] ??
        _displayTab.location.queryParameters['q'] ??
        '';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    for (final controller in _pageBack.values) {
      controller.dispose();
    }
    for (final progress in _pagingProgress.values) {
      progress.dispose();
    }
    super.dispose();
  }

  void _revealActiveTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabContext = _tabKeys[_workspace.activeId]?.currentContext;
      if (tabContext != null) {
        Scrollable.ensureVisible(tabContext, alignment: 0.5);
      }
    });
  }

  void _commitWorkspace() {
    _restoreSearch();
    context.go(_workspace.active.route.toString());
    _revealActiveTab();
  }

  void _newTab() {
    if (_dualTabs) return;
    if (_workspace.tabs.length >= WorkspaceTabs.maximumTabs) {
      showAppNotice(context, '最多打开 16 个标签页，请先关闭不用的标签');
      return;
    }
    setState(_workspace.addBrowseTab);
    _commitWorkspace();
  }

  void _selectTab(String id) {
    setState(() => _workspace.select(id));
    _commitWorkspace();
  }

  void _updatePageLocation(WorkspaceTab tab, Uri location) {
    if (!mounted ||
        !_workspace.updateLocation(
          tab.id,
          location,
          expectedLocation: tab.location,
        )) {
      return;
    }
    setState(() {});
    if (tab.id == _workspace.activeId) _commitWorkspace();
  }

  void _closeTab(String id) {
    final wasActive = id == _workspace.activeId;
    if (!_workspace.close(id)) return;
    _tabKeys.remove(id);
    _searchDrafts.remove(id);
    _pageStorage.remove(id);
    _prunePages();
    setState(() {});
    if (wasActive) _commitWorkspace();
  }

  bool _goBack() {
    if (_goBackWithinPage()) return true;
    if (!(_canReturnFromMessages
        ? _workspace.returnFromMessages()
        : _desktopDual
        ? _workspace.goBackBrowsing()
        : _workspace.goBack())) {
      return false;
    }
    _prunePages();
    setState(() {});
    _commitWorkspace();
    return true;
  }

  Future<void> _confirmAndroidExit() async {
    if (_exitConfirmationOpen) return;
    _exitConfirmationOpen = true;
    final location = widget.location;
    try {
      final exit = await showAppDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('退出哔帆？'),
          content: const Text('确定要退出应用吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('退出'),
            ),
          ],
        ),
      );
      if (exit == true &&
          mounted &&
          widget.location == location &&
          !_canGoBack) {
        await SystemNavigator.pop();
      }
    } finally {
      _exitConfirmationOpen = false;
    }
  }

  void _closePlaybackWindow() {
    final id = _workspace.playbackId;
    if (id == null) return;
    _closeTab(id);
    widget.onActivateBrowser?.call();
  }

  void _playbackWindowBack() {
    final id = _workspace.playbackId;
    if (id == null) return;
    if (_pageBack[id]?.goBack() ?? false) return;
    _workspace.select(id);
    if (!_workspace.goBack()) return;
    _prunePages();
    setState(() {});
    _commitWorkspace();
    if (!_workspace.active.isPlayback) widget.onActivateBrowser?.call();
  }

  void _playbackWindowError(Object error) {
    if (!mounted || _windowFailed) return;
    setState(() => _windowFailed = true);
    showAppNotice(context, '独立播放窗口未能打开，已保留当前播放页面，请重试或切换导航模式');
  }

  void _cycleTabs({bool backwards = false}) {
    if (_desktopDual) {
      setState(() => _windowActivation++);
      return;
    }
    setState(() => _workspace.cycle(backwards: backwards));
    _commitWorkspace();
  }

  void _search(String input) {
    final query = input.trim();
    if (query.isEmpty) return;
    context.go(Uri(path: '/search', queryParameters: {'q': query}).toString());
  }

  void _selectChannel(HomeChannel channel) {
    _lastChannels[sectionForLocation(
          Uri(path: '/', queryParameters: {'channel': channel.name}),
          compact: false,
        )] =
        channel;
    final tab = _displayTab.isBrowse ? _displayTab : _workspace.tabs.first;
    context.go(
      Uri(
        path: '/',
        queryParameters: {
          'channel': channel.name,
          'tab': tab.id,
          'section': ?_lastSections[channel],
        },
      ).toString(),
    );
  }

  void _rememberSection(Uri location) {
    if (location.path == '/settings') {
      _lastSettingsCategory = SettingsCategory.fromName(
        location.queryParameters['section'],
      );
      return;
    }
    if (location.path != '/') return;
    final requestedChannel =
        HomeChannel.values
            .where((value) => value.name == location.queryParameters['channel'])
            .firstOrNull ??
        HomeChannel.recommended;
    final channel = requestedChannel == HomeChannel.ranking
        ? HomeChannel.popular
        : requestedChannel;
    _lastChannels[sectionForLocation(location, compact: false)] = channel;
    final section = location.queryParameters['section'];
    if (section != null && channel.sections.contains(section)) {
      _lastSections[channel] = section;
    } else if (channel == HomeChannel.live) {
      _lastSections[channel] = channel.sections.first;
    } else if (requestedChannel == HomeChannel.ranking) {
      _lastSections[channel] = '排行榜';
    }
  }

  void _selectLiveSection(String section) {
    _lastSections[HomeChannel.live] = section;
    final tab = _displayTab.isBrowse ? _displayTab : _workspace.tabs.first;
    context.go(
      Uri(
        path: '/',
        queryParameters: {
          'channel': HomeChannel.live.name,
          'section': section,
          'tab': tab.id,
        },
      ).toString(),
    );
  }

  CommandOutcome _workspaceCommand(Object command, InputStroke stroke) {
    if (stroke.phase == InputPhase.up) return CommandOutcome.noOp;
    InputScope.of<Object>(context)?.dispatcher.beforeNavigation();
    switch (command) {
      case ShortcutAction.newTab:
        _newTab();
      case ShortcutAction.closeTab:
        if (_desktopDual) {
          _goBack();
        } else if (!_goBackWithinPage()) {
          _closeTab(_workspace.activeId);
        }
      case ReservedShortcut.nextTab:
        _cycleTabs();
      case ReservedShortcut.previousTab:
        _cycleTabs(backwards: true);
    }
    return CommandOutcome.completed;
  }

  @override
  Widget build(BuildContext context) {
    final dispatcher = InputScope.of<Object>(context)?.dispatcher;
    if (dispatcher is ShortcutCoordinator) {
      dispatcher.configure(widget.shortcuts);
    }
    // Keyboard resizing changes geometry, not the cached pages' configuration.
    final pages = _pages(context);
    final main = CommandTargetScope<Object>(
      scope: CommandScope.workspace,
      commands: {
        for (final command in <Object>[
          ShortcutAction.newTab,
          ShortcutAction.closeTab,
          ReservedShortcut.nextTab,
          ReservedShortcut.previousTab,
        ])
          command: (stroke) => _workspaceCommand(command, stroke),
      },
      child: PopScope<Object?>(
        canPop: !_android && !_canGoBack,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_goBack() && _android) _confirmAndroidExit();
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            floatingActionButton:
                _dualTabs &&
                    !_desktopDual &&
                    !_workspace.active.isPlayback &&
                    _workspace.playbackId != null
                ? FloatingActionButton.small(
                    tooltip: '返回播放',
                    onPressed: () => _selectTab(_workspace.playbackId!),
                    child: const Icon(Icons.play_arrow_rounded),
                  )
                : null,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 600;
                  final wide = constraints.maxWidth >= 1180;
                  final colors = Theme.of(context).colorScheme;
                  return Column(
                    children: [
                      if (_dualTabs) ...[
                        if (widget.windowControlsBuilder != null)
                          _dualWindowCaption(context)
                        else if (!_desktopDual && _workspace.active.isPlayback)
                          _mobilePlaybackHeader(context),
                      ] else
                        _tabStrip(context),
                      Expanded(
                        child: Row(
                          children: [
                            SizedBox(
                              width: compact ? 0 : (wide ? 164 : 76),
                              child: Offstage(
                                offstage: compact,
                                child: _sideNavigation(context, extended: wide),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: compact
                                    ? EdgeInsets.zero
                                    : const EdgeInsets.fromLTRB(0, 12, 16, 16),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    compact ? 0 : 18,
                                  ),
                                  child: ColoredBox(
                                    color: colors.surface,
                                    child: Column(
                                      children: [
                                        if (_showBackButton &&
                                            widget.windowControlsBuilder ==
                                                null &&
                                            _displayTab.isProfile)
                                          SizedBox(
                                            key: const ValueKey(
                                              'workspace-profile-back-header',
                                            ),
                                            height: 42,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: _backButton(),
                                            ),
                                          ),
                                        if (_displayTab.location.path !=
                                                '/search' &&
                                            !_displayTab.isPlayback &&
                                            !_displayTab.isProfile)
                                          LayoutBuilder(
                                            builder: (context, bounds) =>
                                                _navigationHeader(
                                                  context,
                                                  bounds,
                                                  _channelBar(
                                                    context,
                                                    compact: compact,
                                                  ),
                                                  compact: compact,
                                                ),
                                          ),
                                        Expanded(child: pages),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (compact &&
                          !_displayTab.isPlayback &&
                          !_displayTab.isProfile)
                        _animatedBottomNavigation(context),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    final windowBuilder = widget.playbackWindowBuilder;
    if (windowBuilder == null) return main;
    final playback = _desktopDual
        ? _workspace.tabs
              .where((tab) => tab.id == _workspace.playbackId)
              .firstOrNull
        : null;
    return windowBuilder(
      context,
      child: main,
      playback: playback == null
          ? null
          : _page(context, playback, active: true),
      activationToken: _windowActivation,
      onClose: _closePlaybackWindow,
      onBack: _playbackWindowBack,
      onError: _playbackWindowError,
    );
  }

  Widget _dualWindowCaption(BuildContext context) => SizedBox(
    key: const ValueKey('dual-window-caption'),
    height: 32,
    child: Row(
      children: [
        if (_showBackButton) _backButton(),
        Expanded(
          child:
              widget.dragRegionBuilder?.call(
                context,
                const Padding(
                  padding: EdgeInsets.only(left: 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('哔帆', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ) ??
              const SizedBox.expand(),
        ),
        widget.windowControlsBuilder!(context),
      ],
    ),
  );

  Widget _mobilePlaybackHeader(BuildContext context) => SizedBox(
    height: 44,
    child: Row(
      children: [
        IconButton(
          tooltip: '返回上一视频',
          onPressed: _playbackWindowBack,
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(
            _workspace.active.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: '关闭播放',
          onPressed: _closePlaybackWindow,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  Widget _pages(BuildContext context) {
    final builder = widget.pageBuilder;
    if (builder == null) {
      return PageBackScope(
        controller: _backFor(_workspace.activeId),
        child: widget.child,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // go_router needs its shell Navigator mounted to dispatch system back
        // and dismiss dialogs. Its feature routes only build placeholders.
        Offstage(child: widget.child),
        for (final tab in _workspace.tabs)
          if (!_desktopDual || tab.id != _workspace.playbackId)
            _page(context, tab, active: tab.id == _displayTab.id),
      ],
    );
  }

  Widget _page(
    BuildContext context,
    WorkspaceTab tab, {
    required bool active,
  }) => Offstage(
    key: _pageKeys.putIfAbsent(tab.id, GlobalKey.new),
    offstage: !active,
    // Keep account listeners active for cached pages. Riverpod pauses
    // listeners below a disabled TickerMode, delaying logout cleanup.
    child: FocusScope(
      canRequestFocus: active,
      skipTraversal: !active,
      child: WorkspaceActivity(
        active: active,
        child: WorkspacePlaybackSelection(
          tabId: _desktopDual ? _workspace.playbackId : null,
          child: PageStorage(
            bucket: _pageStorage.putIfAbsent(tab.id, PageStorageBucket.new),
            child: WorkspacePageHeader(
              builder: _searchHeader,
              child: WorkspacePageNavigation(
                navigate: (location) => _updatePageLocation(tab, location),
                child: TabPagingScope(
                  progress: _pagingFor(tab),
                  child: PageBackScope(
                    controller: _backFor(tab.id),
                    child:
                        widget.pageBuilder?.call(context, tab) ?? widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void _selectSection(WorkspaceSection section, {required bool compact}) {
    switch (section) {
      case WorkspaceSection.home:
        _selectChannel(_lastChannels[section] ?? HomeChannel.recommended);
      case WorkspaceSection.dynamic:
        _selectChannel(_lastChannels[section] ?? HomeChannel.dynamic);
      case WorkspaceSection.live:
        _selectChannel(HomeChannel.live);
      case WorkspaceSection.mine:
        context.go('/me');
      case WorkspaceSection.messages:
        context.go('/messages');
      case WorkspaceSection.downloads:
        context.go('/downloads');
      case WorkspaceSection.settings:
        context.go(
          Uri(
            path: '/settings',
            queryParameters: {'section': _lastSettingsCategory.name},
          ).toString(),
        );
    }
  }

  IconData _sectionIcon(WorkspaceSection section, {bool selected = false}) =>
      switch (section) {
        WorkspaceSection.home =>
          selected ? Icons.home_rounded : Icons.home_outlined,
        WorkspaceSection.dynamic => Icons.rss_feed_rounded,
        WorkspaceSection.live =>
          selected ? Icons.live_tv_rounded : Icons.live_tv_outlined,
        WorkspaceSection.mine =>
          selected ? Icons.person_rounded : Icons.person_outline_rounded,
        WorkspaceSection.messages => Icons.chat_bubble_outline_rounded,
        WorkspaceSection.downloads => Icons.file_download_outlined,
        WorkspaceSection.settings => Icons.tune_rounded,
      };

  Widget _sideNavigation(BuildContext context, {required bool extended}) {
    final colors = Theme.of(context).colorScheme;
    final section = sectionForLocation(_displayTab.location, compact: false);
    Widget entry(
      String label,
      IconData icon,
      bool selected,
      VoidCallback onTap, {
      Key? key,
      bool iconOnly = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Tooltip(
        message: label,
        child: Material(
          color: selected ? colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Semantics(
              label: iconOnly ? label : null,
              selected: selected,
              button: true,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: extended ? 14 : 4,
                  vertical: iconOnly ? 8 : 13,
                ),
                child: iconOnly
                    ? Center(
                        child: Icon(
                          icon,
                          size: 21,
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      )
                    : extended
                    ? Row(
                        children: [
                          Icon(
                            icon,
                            size: 21,
                            color: selected
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? colors.primary
                                    : colors.onSurface,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Icon(
                            icon,
                            size: 21,
                            color: selected
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: selected
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactTools = constraints.maxHeight < 430;
        return Column(
          key: const ValueKey('workspace-side-navigation'),
          children: [
            Expanded(
              child: ListView(
                key: const ValueKey('workspace-primary-navigation'),
                padding: const EdgeInsets.only(top: 20),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/branding/app_icon.png',
                          key: const ValueKey('workspace-brand-logo'),
                          width: 36,
                          height: 36,
                          excludeFromSemantics: true,
                        ),
                        if (extended) ...[
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              '哔帆',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  for (final item in const [
                    WorkspaceSection.home,
                    WorkspaceSection.dynamic,
                    WorkspaceSection.live,
                    WorkspaceSection.mine,
                  ])
                    entry(
                      item.label,
                      _sectionIcon(
                        item,
                        selected: !_displayTab.isPlayback && section == item,
                      ),
                      !_displayTab.isPlayback && section == item,
                      () => _selectSection(item, compact: false),
                      key: ValueKey('workspace-nav-${item.name}'),
                    ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.75,
              ),
              // Extremely short windows retain access to every utility while
              // leaving the primary navigation its own scrollable region.
              child: SingleChildScrollView(
                key: const ValueKey('workspace-utility-navigation'),
                reverse: true,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Divider(height: 16),
                      ),
                      entry(
                        '消息',
                        _sectionIcon(WorkspaceSection.messages),
                        section == WorkspaceSection.messages,
                        () => _selectSection(
                          WorkspaceSection.messages,
                          compact: false,
                        ),
                        key: const ValueKey('workspace-nav-messages'),
                        iconOnly: compactTools,
                      ),
                      entry(
                        '下载',
                        _sectionIcon(WorkspaceSection.downloads),
                        section == WorkspaceSection.downloads,
                        () => _selectSection(
                          WorkspaceSection.downloads,
                          compact: false,
                        ),
                        key: const ValueKey('workspace-nav-downloads'),
                        iconOnly: compactTools,
                      ),
                      entry(
                        '设置',
                        _sectionIcon(WorkspaceSection.settings),
                        section == WorkspaceSection.settings,
                        () => _selectSection(
                          WorkspaceSection.settings,
                          compact: false,
                        ),
                        key: const ValueKey('workspace-nav-settings'),
                        iconOnly: compactTools,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _animatedBottomNavigation(BuildContext context) {
    // Scaffold clears MediaQuery's body insets. Read this view's inset to
    // hide immediately on keyboard opening and animate only the return.
    final visible = View.of(context).viewInsets.bottom == 0;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final target = visible ? 1.0 : 0.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: target, end: target),
      duration: visible && !disableAnimations
          ? const Duration(milliseconds: 180)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      child: _bottomNavigation(context),
      builder: (context, value, child) {
        final progress = disableAnimations ? 1.0 : value;
        if (!visible || progress == 0) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          ignoring: progress < 1,
          child: ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: progress,
              child: Opacity(opacity: progress, child: child),
            ),
          ),
        );
      },
    );
  }

  Widget _bottomNavigation(BuildContext context) {
    const sections = [
      WorkspaceSection.home,
      WorkspaceSection.dynamic,
      WorkspaceSection.mine,
      WorkspaceSection.settings,
    ];
    final selected = sectionForLocation(_displayTab.location, compact: true);
    if (!sections.contains(selected)) {
      return _unselectedBottomNavigation(context, sections);
    }
    return NavigationBar(
      key: const ValueKey('workspace-bottom-navigation'),
      height: _bottomNavigationHeight,
      labelPadding: EdgeInsets.zero,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final colors = Theme.of(context).colorScheme;
        return _bottomNavigationLabelStyle.copyWith(
          color: states.contains(WidgetState.selected)
              ? colors.onSurface
              : colors.onSurfaceVariant,
        );
      }),
      selectedIndex: sections.indexOf(selected),
      onDestinationSelected: (index) =>
          _selectSection(sections[index], compact: true),
      destinations: [
        for (final item in sections)
          NavigationDestination(
            key: ValueKey('workspace-bottom-${item.name}'),
            icon: Icon(_sectionIcon(item), size: _bottomNavigationIconSize),
            selectedIcon: Icon(
              _sectionIcon(item, selected: true),
              size: _bottomNavigationIconSize,
            ),
            label: item.label,
          ),
      ],
    );
  }

  Widget _unselectedBottomNavigation(
    BuildContext context,
    List<WorkspaceSection> sections,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final barTheme = NavigationBarTheme.of(context);
    return Material(
      key: const ValueKey('workspace-bottom-navigation'),
      color: barTheme.backgroundColor ?? colors.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _bottomNavigationHeight,
          child: Row(
            children: [
              for (final section in sections)
                Expanded(
                  child: Tooltip(
                    message: section.label,
                    child: Semantics(
                      selected: false,
                      button: true,
                      label: section.label,
                      child: InkWell(
                        key: ValueKey('workspace-bottom-${section.name}'),
                        onTap: () => _selectSection(section, compact: true),
                        child: Center(
                          child: ExcludeSemantics(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _sectionIcon(section),
                                  size: _bottomNavigationIconSize,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  section.label,
                                  style: _bottomNavigationLabelStyle.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabStrip(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: (constraints.maxWidth - 66).clamp(
                          0,
                          double.infinity,
                        ),
                      ),
                      child: _horizontalTabs(
                        key: const ValueKey('workspace-tab-strip'),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final tab in _workspace.visibleTabs)
                              _tab(context, tab),
                          ],
                        ),
                      ),
                    ),
                    if (!_dualTabs)
                      SizedBox(
                        width: 42,
                        child: IconButton(
                          key: const ValueKey('new-workspace-tab'),
                          tooltip: '新建标签页 (Ctrl+T)',
                          onPressed: _newTab,
                          icon: const Icon(Icons.add, size: 18),
                        ),
                      ),
                    Expanded(
                      child:
                          widget.dragRegionBuilder?.call(
                            context,
                            const SizedBox.expand(),
                          ) ??
                          const SizedBox.expand(),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.windowControlsBuilder case final builder?
                when workspaceHeaderVisible)
              builder(context),
          ],
        ),
      ),
    );
  }

  Widget _backButton() => IconButton(
    key: const ValueKey('workspace-back'),
    tooltip: '返回上一页',
    onPressed: _canGoBack ? _goBack : null,
    icon: const Icon(Icons.arrow_back, size: 20),
  );

  Widget _horizontalTabs({
    required Key key,
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) => ScrollConfiguration(
    behavior: const SmoothScrollBehavior(horizontalMouseWheel: true),
    child: SingleChildScrollView(
      key: key,
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: child,
    ),
  );

  Widget _tab(BuildContext context, WorkspaceTab tab) {
    final selected = tab.id == _workspace.activeId;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: _tabKeys.putIfAbsent(tab.id, GlobalKey.new),
      padding: const EdgeInsets.only(left: 3, top: 4),
      child: Material(
        color: selected ? colors.surface : Colors.transparent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        child: InkWell(
          key: ValueKey('workspace-tab-${tab.id}'),
          onTap: () => _selectTab(tab.id),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          child: Semantics(
            selected: selected,
            button: true,
            child: SizedBox(
              width: tab.pinned ? 116 : 176,
              height: 38,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(_tabIcon(tab), size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _dualTabs && !tab.isPlayback
                          ? '浏览 · ${tab.title}'
                          : tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (!tab.pinned && (!_dualTabs || tab.isPlayback))
                    IconButton(
                      key: ValueKey('close-workspace-tab-${tab.id}'),
                      tooltip: '关闭${tab.title}',
                      onPressed: () => _closeTab(tab.id),
                      constraints: const BoxConstraints.tightFor(
                        width: 30,
                        height: 30,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close, size: 13),
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _tabIcon(WorkspaceTab tab) => switch (tab.location.path) {
    '/'
        when sectionForLocation(tab.location, compact: false) ==
            WorkspaceSection.dynamic =>
      _sectionIcon(WorkspaceSection.dynamic),
    '/me' => _sectionIcon(WorkspaceSection.mine),
    '/messages' => _sectionIcon(WorkspaceSection.messages),
    '/downloads' => _sectionIcon(WorkspaceSection.downloads),
    '/search' => BiliIcons.search,
    '/history' => BiliIcons.history,
    '/settings' => _sectionIcon(WorkspaceSection.settings),
    _ =>
      tab.isProfile
          ? Icons.person_outline
          : tab.isPlayback
          ? BiliIcons.playCount
          : BiliIcons.home,
  };

  Widget? _channelBar(BuildContext context, {required bool compact}) {
    final active = _displayTab;
    if (active.location.path == '/history' ||
        active.location.path == '/downloads' ||
        active.location.path == '/messages' ||
        active.location.path == '/settings' ||
        active.location.path == '/me') {
      return null;
    }
    if (!compact && active.location.queryParameters['channel'] == 'live') {
      return _liveSectionBar(context);
    }
    final selected = active.isBrowse
        ? HomeChannel.primaryValues
              .where(
                (channel) =>
                    channel.name ==
                    (active.location.queryParameters['channel'] == 'ranking'
                        ? 'popular'
                        : active.location.queryParameters['channel'] ??
                              'recommended'),
              )
              .firstOrNull
        : null;
    final section = sectionForLocation(active.location, compact: compact);
    final tabs = channelsForSection(section, compact: compact);
    final equalWidthTabs = compact && section == WorkspaceSection.dynamic;
    return SizedBox(
      height: PageTabStyle.barHeight,
      child: LayoutBuilder(
        builder: (context, constraints) => _horizontalTabs(
          key: const ValueKey('home-channel-strip'),
          padding: equalWidthTabs
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 10),
          child: PagingTabStrip<HomeChannel>(
            tabs: tabs,
            progressTabs: HomeChannel.primaryValues,
            value: selected,
            progress: _pagingFor(active),
            onSelected: _selectChannel,
            itemKey: (channel) => ValueKey('channel-${channel.name}'),
            spacing: equalWidthTabs ? 0 : 3,
            buttonStyle: PageTabStyle.buttonStyle(context).copyWith(
              fixedSize: equalWidthTabs
                  ? WidgetStatePropertyAll(
                      Size.fromWidth(constraints.maxWidth / tabs.length),
                    )
                  : null,
            ),
            labelBuilder: (context, channel) =>
                PageTabStyle.label(channel.label, icon: _channelIcon(channel)),
          ),
        ),
      ),
    );
  }

  Widget _liveSectionBar(BuildContext context) {
    final sections = HomeChannel.live.sections;
    final requested = _displayTab.location.queryParameters['section'];
    final selected = sections.contains(requested) ? requested : sections.first;
    return SizedBox(
      height: PageTabStyle.barHeight,
      child: _horizontalTabs(
        key: const ValueKey('workspace-live-section-strip'),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: PagingTabStrip<String>(
          tabs: sections,
          value: selected,
          onSelected: _selectLiveSection,
          itemKey: (section) => ValueKey('workspace-live-section-$section'),
          buttonStyle: PageTabStyle.buttonStyle(context),
          labelBuilder: (context, section) => PageTabStyle.label(
            section,
            icon: switch (section) {
              '我的关注' => Icons.favorite_border_rounded,
              '观看记录' => Icons.history_rounded,
              _ => Icons.live_tv_outlined,
            },
          ),
        ),
      ),
    );
  }

  Widget _searchHeader(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _navigationHeader(
      context,
      constraints,
      const SearchCategoryBar(),
      showTools: true,
    ),
  );

  bool _navigationToolsVisible({required bool compact}) =>
      switch (sectionForLocation(_displayTab.location, compact: false)) {
        WorkspaceSection.dynamic => !compact,
        WorkspaceSection.mine ||
        WorkspaceSection.messages ||
        WorkspaceSection.downloads ||
        WorkspaceSection.settings => false,
        _ => true,
      };

  Widget _navigationHeader(
    BuildContext context,
    BoxConstraints constraints,
    Widget? navigation, {
    bool? showTools,
    bool compact = false,
  }) {
    if (!(showTools ?? _navigationToolsVisible(compact: compact))) {
      if (navigation == null &&
          _dualTabs &&
          widget.windowControlsBuilder == null &&
          _showBackButton &&
          _displayTab.location.path != '/me') {
        return SizedBox(
          key: const ValueKey('workspace-page-back-header'),
          height: 42,
          child: Align(alignment: Alignment.centerLeft, child: _backButton()),
        );
      }
      return navigation ?? const SizedBox.shrink();
    }
    return constraints.maxWidth < 760
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [_tools(context), ?navigation],
          )
        : SizedBox(
            height: PageTabStyle.barHeight,
            child: Row(
              children: [
                SizedBox(
                  width: constraints.maxWidth >= 1300 ? 470 : 380,
                  child: _tools(context),
                ),
                if (navigation != null) Expanded(child: navigation),
              ],
            ),
          );
  }

  IconData _channelIcon(HomeChannel channel) => switch (channel) {
    HomeChannel.recommended => BiliIcons.home,
    HomeChannel.popular => Icons.local_fire_department_outlined,
    HomeChannel.dynamic => Icons.rss_feed_rounded,
    HomeChannel.videoDynamic => Icons.video_library_outlined,
    HomeChannel.bangumi => Icons.live_tv_outlined,
    HomeChannel.guochuang => Icons.animation_outlined,
    HomeChannel.live => Icons.live_tv,
    HomeChannel.cinema => Icons.movie_outlined,
    HomeChannel.categories => BiliIcons.categories,
    HomeChannel.ranking => BiliIcons.ranking,
    HomeChannel.watchLater => BiliIcons.watchLater,
    HomeChannel.favorites => BiliIcons.favorite,
  };

  Widget _tools(BuildContext context) => SizedBox(
    key: const ValueKey('workspace-common-tools'),
    height: 52,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          if (_showBackButton && widget.windowControlsBuilder == null)
            _backButton(),
          if (widget.accountBuilder case final builder?) ...[
            builder(context),
            const SizedBox(width: 5),
          ],
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                key: const ValueKey('workspace-search'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 12),
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: '搜索视频、UP 主、番剧',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  suffixIcon: IconButton(
                    tooltip: '搜索',
                    onPressed: () => _search(_searchController.text),
                    icon: const Icon(BiliIcons.search, size: 17),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          if (_displayTab.location.path != '/' &&
              _displayTab.location.path != '/search' &&
              MediaQuery.sizeOf(context).width >= 600) ...[
            _tool('观看历史', BiliIcons.history, '/history'),
            _tool('下载', Icons.download_outlined, '/downloads'),
            _tool('设置', BiliIcons.settings, '/settings'),
          ],
        ],
      ),
    ),
  );
  Widget _tool(String tooltip, IconData icon, String route) => IconButton(
    tooltip: tooltip,
    onPressed: () => route == '/settings'
        ? _selectSection(WorkspaceSection.settings, compact: false)
        : context.go(route),
    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
    padding: EdgeInsets.zero,
    icon: Icon(icon, size: 18),
  );
}
