import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/video.dart';
import '../../../shared/ui/responsive_card_grid.dart';
import '../../../shared/ui/video_card.dart';
import '../application/feed_controller.dart';
import '../domain/home_channel.dart';

/// The grid observes list membership; each mounted card owns its feedback view.
final class FeedVideoGrid extends StatelessWidget {
  const FeedVideoGrid({
    super.key,
    required this.items,
    required this.channel,
    required this.onReject,
    required this.onUndo,
    this.previousStartIndex,
  });

  final List<VideoSummary> items;
  final HomeChannel channel;
  final ValueChanged<VideoSummary> onReject;
  final ValueChanged<VideoId> onUndo;
  final int? previousStartIndex;

  Widget _grid(int start, int end) => SliverResponsiveCardGrid(
    itemCount: end - start,
    itemBuilder: (context, offset) {
      final index = start + offset;
      return _FeedVideoCard(
        key: ValueKey((items[index].id, index)),
        video: items[index],
        recommended: channel == HomeChannel.recommended,
        onReject: onReject,
        onUndo: onUndo,
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final boundary = previousStartIndex;
    if (boundary == null || boundary < 0 || boundary >= items.length) {
      return _grid(0, items.length);
    }
    return SliverMainAxisGroup(
      slivers: [
        if (boundary > 0) _grid(0, boundary),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('上次看到这里'),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
        ),
        _grid(boundary, items.length),
      ],
    );
  }
}

typedef _FeedbackState = ({bool rejected, bool busy, bool uncertain});

final class _FeedVideoCard extends ConsumerStatefulWidget {
  const _FeedVideoCard({
    super.key,
    required this.video,
    required this.recommended,
    required this.onReject,
    required this.onUndo,
  });

  final VideoSummary video;
  final bool recommended;
  final ValueChanged<VideoSummary> onReject;
  final ValueChanged<VideoId> onUndo;

  @override
  ConsumerState<_FeedVideoCard> createState() => _FeedVideoCardState();
}

final class _FeedVideoCardState extends ConsumerState<_FeedVideoCard> {
  VideoCard? _card;
  _FeedbackState? _feedback;

  @override
  void didUpdateWidget(_FeedVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.video, widget.video) ||
        oldWidget.recommended != widget.recommended) {
      _card = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    var feedback = (rejected: false, busy: false, uncertain: false);
    if (widget.recommended) {
      final controller = ref.watch(feedControllerProvider.notifier);
      feedback = ref.watch(
        feedControllerProvider.select((current) {
          final state = controller.stateForChannel(
            HomeChannel.recommended,
            current: current,
          );
          return (
            rejected: state.rejected.contains(widget.video.id),
            busy: state.rejecting.contains(widget.video.id),
            uncertain: state.uncertainRestorations.contains(widget.video.id),
          );
        }),
      );
    }
    if (_feedback != feedback) {
      _feedback = feedback;
      _card = null;
    }
    // Sliver delegates update when a page is appended. Reuse the heavy card
    // only for unchanged immutable data; cache lifetime is the mounted tile,
    // not the entire loaded feed. Inherited theme/activity still reach it.
    return _card ??= VideoCard(
      key: ValueKey(widget.video.id),
      video: widget.video,
      onTap: () => context.go('/video/${widget.video.id.value}'),
      onOpenUser: (id) => context.go('/user/${id.value}'),
      showRecommendationReason: widget.recommended,
      feedback: feedback.rejected
          ? VideoCardFeedback(
              busy: feedback.busy,
              onUndo: feedback.uncertain
                  ? null
                  : () => widget.onUndo(widget.video.id),
            )
          : null,
      menu: widget.recommended
          ? VideoCardMenu(
              actions: const [
                VideoCardMenuAction.notInterested,
                VideoCardMenuAction.watchLater,
              ],
              busy: feedback.busy,
              // Read current callbacks and data, even after a parent update
              // that deliberately reused this card (for example login state).
              onSelected: (action) {
                if (action == VideoCardMenuAction.notInterested) {
                  widget.onReject(widget.video);
                }
              },
            )
          : null,
    );
  }
}
