/// An in-memory browsing workspace. Routes remain shareable without tab IDs.
final class WorkspaceTab {
  const WorkspaceTab({
    required this.id,
    required this.location,
    this.pinned = false,
  });

  final String id;
  final Uri location;
  final bool pinned;

  bool get isVideo => location.path.startsWith('/video/');
  bool get isPgc => location.path.startsWith('/pgc/');
  bool get isLive => location.path.startsWith('/live/');
  bool get isOffline => location.path.startsWith('/offline/');
  bool get isPlayback => isVideo || isPgc || isLive || isOffline;
  bool get isProfile =>
      location.pathSegments.length == 2 &&
      location.pathSegments.first == 'user';
  bool get isBrowse => location.path == '/';
  bool get isAccount => location.path == '/me';
  bool get isMessages => location.path == '/messages';
  bool get isDownloads => location.path == '/downloads';
  bool get isSettings => location.path == '/settings';
  bool get isRoot =>
      isBrowse || isAccount || isMessages || isDownloads || isSettings;

  String get title {
    if (isBrowse) return pinned ? '首页' : '浏览';
    if (location.path == '/search') {
      final query = location.queryParameters['q'] ?? '';
      return query.isEmpty ? '搜索' : '搜索：$query';
    }
    if (location.path == '/history') return '观看历史';
    if (location.path == '/messages') return '我的消息';
    if (location.path == '/settings') return '设置';
    if (location.path == '/downloads') return '下载';
    if (location.path == '/me') return '我的';
    if (isOffline) return '离线播放';
    if (isVideo) return location.pathSegments.last;
    if (isPgc) return '影视 · ${location.pathSegments.last}';
    if (isLive) return '直播 · ${location.pathSegments.last}';
    if (isProfile) return '用户主页 · ${location.pathSegments.last}';
    return '浏览';
  }

  Uri get route => location.replace(
    queryParameters: {...location.queryParameters, 'tab': id},
  );
}

final class WorkspaceTabs {
  static const maximumTabs = 16;
  static const maximumHistory = 64;
  final List<WorkspaceTab> _tabs = [
    WorkspaceTab(
      id: 'home',
      location: Uri(path: '/'),
      pinned: true,
    ),
  ];
  String _activeId = 'home';
  int _nextId = 1;
  final List<String> _backHistory = [];
  bool _dualMode = false;
  String _browseId = 'home';
  String? _playbackId;
  final List<Uri> _playbackHistory = [];

  /// Dual mode projects the retained workspace onto a browsing and a playback
  /// slot. Existing tabs survive mode changes; new media reuse one page/session.
  void setDualMode(bool enabled) {
    if (_dualMode == enabled) return;
    _dualMode = enabled;
    if (!enabled) return;
    if (active.isPlayback) {
      _playbackId = activeId;
    } else {
      _browseId = activeId;
    }
    if (!_tabs.any((tab) => tab.id == _playbackId)) {
      _playbackId = _tabs.where((tab) => tab.isPlayback).lastOrNull?.id;
    }
    if (!_tabs.any((tab) => tab.id == _browseId && !tab.isPlayback)) {
      _browseId = 'home';
    }
  }

  List<WorkspaceTab> get visibleTabs => !_dualMode
      ? tabs
      : [
          _tabs.firstWhere((tab) => tab.id == _browseId),
          if (_playbackId case final id?) ..._tabs.where((tab) => tab.id == id),
        ];

  String get browseId => _browseId;
  String? get playbackId => _playbackId;
  bool get canGoBackBrowsing => _browseId != 'home';

  /// Desktop dual windows keep media navigation out of the browser's Back.
  bool goBackBrowsing() {
    if (!canGoBackBrowsing) return false;
    final leaving = _browseId;
    var destination = 'home';
    while (_backHistory.isNotEmpty) {
      final id = _backHistory.removeLast();
      if (id == leaving ||
          !_tabs.any((tab) => tab.id == id && !tab.isPlayback)) {
        continue;
      }
      destination = id;
      break;
    }
    _activeId = _browseId = destination;
    // Change the selected browsing slot before closing it; ordinary close
    // intentionally protects the currently visible dual browsing slot.
    close(leaving);
    _trimHistory();
    return true;
  }

  void clearPlaybackHistory() => _playbackHistory.clear();

  List<WorkspaceTab> get tabs => List.unmodifiable(_tabs);
  String get activeId => _activeId;
  int get activeIndex => _tabs.indexWhere((tab) => tab.id == _activeId);
  WorkspaceTab get active => _tabs[activeIndex];
  bool get canGoBack => _dualMode && active.isPlayback
      ? true
      : _dualMode
      ? canGoBackBrowsing
      : _backHistory.any((id) => id != activeId);

  void _activate(String id) {
    if (id != _activeId) {
      _backHistory.add(_activeId);
      if (_backHistory.length > maximumHistory) _backHistory.removeAt(0);
      _activeId = id;
    }
    if (active.isPlayback) {
      if (_playbackId != id) _playbackHistory.clear();
      _playbackId = id;
    } else {
      _browseId = id;
    }
  }

  /// Back traverses visits, rather than the visual order of the tab strip.
  bool goBack() {
    if (!canGoBack) return false;
    if (_dualMode && active.isPlayback) {
      if (_playbackHistory.isNotEmpty) {
        updateLocation(activeId, _playbackHistory.removeLast());
      } else {
        return close(activeId);
      }
      return true;
    }
    if (_dualMode) return goBackBrowsing();
    _trimHistory();
    _activeId = _backHistory.removeLast();
    if (!active.isPlayback) {
      _browseId = _activeId;
    } else if (_playbackId != activeId) {
      _playbackId = activeId;
      _playbackHistory.clear();
    }
    _trimHistory();
    return true;
  }

  void _trimHistory() {
    while (_backHistory.isNotEmpty && _backHistory.last == _activeId) {
      _backHistory.removeLast();
    }
  }

  WorkspaceTab addBrowseTab() {
    if (_dualMode) {
      select(_browseId);
      return active;
    }
    if (_tabs.length >= maximumTabs) return active;
    final tab = WorkspaceTab(
      id: 'tab-${_nextId++}',
      location: Uri(path: '/'),
    );
    _tabs.add(tab);
    _activate(tab.id);
    return tab;
  }

  /// Playback advancement changes a cached page without recording a visit or
  /// selecting it. A closed page must never be recreated by a late callback.
  bool updateLocation(String id, Uri route, {Uri? expectedLocation}) {
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return false;
    final previous = _tabs[index];
    if (expectedLocation != null && previous.location != expectedLocation) {
      return false;
    }
    if (previous.pinned && !WorkspaceTab(id: '', location: route).isRoot) {
      return false;
    }
    final parameters = {...route.queryParameters}..remove('tab');
    _tabs[index] = WorkspaceTab(
      id: previous.id,
      location: route.replace(queryParameters: parameters),
      pinned: previous.pinned,
    );
    return true;
  }

  /// Primary destinations select home; explicit feed tabs and detail routes
  /// retain their independent page identities.
  bool acceptRoute(Uri route) {
    final requestedId = route.queryParameters['tab'];
    final parameters = {...route.queryParameters}..remove('tab');
    final location = route.replace(queryParameters: parameters);
    final target = WorkspaceTab(id: '', location: location);
    if ((target.isRoot && !target.isBrowse) ||
        (target.isBrowse && (requestedId == null || requestedId == 'home'))) {
      _tabs[0] = WorkspaceTab(id: 'home', location: location, pinned: true);
      // Primary destinations share one root identity. Moving between them is
      // a selection, not a visit to a new page in the transient Back stack.
      _activeId = _browseId = 'home';
      _trimHistory();
      return true;
    }
    if (_dualMode && target.isPlayback && _playbackId != null) {
      final slot = _tabs.firstWhere((tab) => tab.id == _playbackId);
      // Route commits and part/quality updates are not new media visits.
      if (slot.location.path != location.path) {
        _playbackHistory.add(slot.location);
        if (_playbackHistory.length > maximumTabs) {
          _playbackHistory.removeAt(0);
        }
      }
      updateLocation(slot.id, location);
      _activate(slot.id);
      return true;
    }
    final known = _tabs.indexWhere((tab) => tab.id == requestedId);
    if (known >= 0 && (!_tabs[known].pinned || target.isRoot)) {
      final previous = _tabs[known];
      _tabs[known] = WorkspaceTab(
        id: previous.id,
        location: location,
        pinned: previous.pinned,
      );
      _activate(previous.id);
      return true;
    }
    if (location.path == '/') {
      _tabs[0] = WorkspaceTab(id: 'home', location: location, pinned: true);
      _activate('home');
      return true;
    }
    final existing = _tabs.where((tab) => tab.location == location).firstOrNull;
    if (existing != null) {
      _activate(existing.id);
      return true;
    }
    if (_tabs.length >= maximumTabs) {
      if (!_dualMode) return false;
      // Dual mode has no tab-close UI. Bound the page cache by releasing the
      // oldest non-home, inactive page instead of blocking further browsing.
      close(
        _tabs
            .firstWhere(
              (tab) =>
                  !tab.pinned &&
                  tab.id != _activeId &&
                  (!_dualMode ||
                      (tab.id != _browseId && tab.id != _playbackId)),
            )
            .id,
      );
    }
    final tab = WorkspaceTab(id: 'tab-${_nextId++}', location: location);
    _tabs.add(tab);
    _activate(tab.id);
    return true;
  }

  void select(String id) {
    if (_tabs.any((tab) => tab.id == id)) _activate(id);
  }

  void cycle({bool backwards = false}) {
    final candidates = visibleTabs;
    final index = candidates.indexWhere((tab) => tab.id == activeId);
    final offset = backwards ? -1 : 1;
    _activate(candidates[(index + offset) % candidates.length].id);
  }

  bool close(String id) {
    if (_dualMode && id == _browseId) return false;
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0 || _tabs[index].pinned) return false;
    final wasActive = _activeId == id;
    _tabs.removeAt(index);
    _backHistory.removeWhere((previous) => previous == id);
    if (id == _playbackId) {
      _playbackId = null;
      _playbackHistory.clear();
    }
    if (id == _browseId) _browseId = 'home';
    if (wasActive) {
      _activeId = _dualMode ? _browseId : _tabs[index > 0 ? index - 1 : 0].id;
    }
    _trimHistory();
    return true;
  }
}
