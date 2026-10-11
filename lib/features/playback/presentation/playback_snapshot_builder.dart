import 'package:bili_player/bili_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A view-only selection of the session's confirmed snapshot. This never
/// samples or throttles the media clock supplied to the danmaku controller.
final class PlaybackSnapshotBuilder<T> extends StatefulWidget {
  const PlaybackSnapshotBuilder({
    super.key,
    required this.snapshots,
    required this.select,
    required this.builder,
  });

  final ValueListenable<PlaybackSnapshot> snapshots;
  final T Function(PlaybackSnapshot snapshot) select;
  final Widget Function(BuildContext context, PlaybackSnapshot snapshot)
  builder;

  @override
  State<PlaybackSnapshotBuilder<T>> createState() =>
      _PlaybackSnapshotBuilderState<T>();
}

final class _PlaybackSnapshotBuilderState<T>
    extends State<PlaybackSnapshotBuilder<T>> {
  late T _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.select(widget.snapshots.value);
    widget.snapshots.addListener(_onSnapshot);
  }

  void _onSnapshot() {
    final selected = widget.select(widget.snapshots.value);
    if (selected == _selected) return;
    setState(() => _selected = selected);
  }

  @override
  void didUpdateWidget(covariant PlaybackSnapshotBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.snapshots, oldWidget.snapshots)) {
      oldWidget.snapshots.removeListener(_onSnapshot);
      widget.snapshots.addListener(_onSnapshot);
    }
    _selected = widget.select(widget.snapshots.value);
  }

  @override
  void dispose() {
    widget.snapshots.removeListener(_onSnapshot);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.snapshots.value);
}
