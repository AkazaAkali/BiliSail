import 'package:flutter/widgets.dart';

/// Workspace actions travel with the player into its fullscreen route.
class PlaybackNavigation extends InheritedWidget {
  const PlaybackNavigation({
    super.key,
    required this.onBack,
    required this.onHome,
    this.showInPlayer = false,
    required super.child,
  });

  final VoidCallback onBack, onHome;
  final bool showInPlayer;

  static PlaybackNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaybackNavigation>();

  @override
  bool updateShouldNotify(PlaybackNavigation oldWidget) =>
      onBack != oldWidget.onBack ||
      onHome != oldWidget.onHome ||
      showInPlayer != oldWidget.showInPlayer;
}
