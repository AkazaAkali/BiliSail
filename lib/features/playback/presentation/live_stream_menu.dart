import 'dart:async';

import 'package:flutter/material.dart';

import '../application/playback_session.dart';
import '../domain/playback_repository.dart';

typedef _LiveSelection = ({int? quality, int? line});

String liveQualityLabel(PlaybackSession session, PlaybackMedia media) =>
    session.requestedQuality == 0
    ? '自动'
    : media.qualityLabels[media.quality] ?? '${media.quality}';

/// Both inline and fullscreen controls use the same live selection menu.
class LiveStreamMenuButton extends StatelessWidget {
  const LiveStreamMenuButton({
    super.key,
    required this.session,
    required this.media,
    required this.onMenuChanged,
  });

  final PlaybackSession session;
  final PlaybackMedia media;
  final ValueChanged<bool> onMenuChanged;

  @override
  Widget build(BuildContext context) {
    final generation = session.sourceGeneration;
    return PopupMenuButton<_LiveSelection>(
      tooltip: '直播清晰度与线路',
      initialValue: (
        quality: session.requestedQuality == 0 ? 0 : media.quality,
        line: null,
      ),
      onOpened: () => onMenuChanged(true),
      onCanceled: () => onMenuChanged(false),
      onSelected: (selection) {
        onMenuChanged(false);
        // An open popup cannot apply a choice to another room/account/source.
        if (generation != session.sourceGeneration) return;
        if (selection.quality case final quality?) {
          unawaited(session.changeQuality(quality));
        } else if (selection.line case final line?) {
          unawaited(session.changeLiveLine(line));
        }
      },
      itemBuilder: (_) => [
        for (final quality in media.qualities)
          PopupMenuItem(
            value: (quality: quality, line: null),
            child: Text(media.qualityLabels[quality] ?? '$quality'),
          ),
        const PopupMenuItem(value: (quality: 0, line: null), child: Text('自动')),
        const PopupMenuDivider(),
        for (var line = 0; line < media.video.urls.length; line++)
          CheckedPopupMenuItem(
            checked: line == session.liveLine,
            value: (quality: null, line: line),
            child: Text('直播线路 ${liveLineLabel(line)}'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(
          child: Text(
            liveQualityLabel(session, media),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
