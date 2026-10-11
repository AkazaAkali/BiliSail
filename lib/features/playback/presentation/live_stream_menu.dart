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
      color: const Color(0xff282828),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        _LiveStreamMenuEntry(
          media: media,
          line: session.liveLine,
          automatic: session.requestedQuality == 0,
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

class _LiveStreamMenuEntry extends PopupMenuEntry<_LiveSelection> {
  const _LiveStreamMenuEntry({
    required this.media,
    required this.line,
    required this.automatic,
  });
  final PlaybackMedia media;
  final int line;
  final bool automatic;

  @override
  double get height => 48;
  @override
  bool represents(_LiveSelection? value) => false;
  @override
  State<_LiveStreamMenuEntry> createState() => _LiveStreamMenuEntryState();
}

class _LiveStreamMenuEntryState extends State<_LiveStreamMenuEntry> {
  bool _showLines = false;

  Widget _row(String label, VoidCallback onTap, {bool selected = false}) =>
      InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 40,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? const Color(0xfffb7299) : Colors.white70,
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: const ValueKey('live-stream-line-header'),
          onTap: () => setState(() => _showLines = !_showLines),
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (_showLines)
                    const Icon(
                      Icons.chevron_left,
                      size: 16,
                      color: Colors.white70,
                    ),
                  Text(
                    liveLineLabel(widget.line),
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  if (!_showLines)
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Colors.white70,
                    ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        if (_showLines)
          for (var line = 0; line < widget.media.video.urls.length; line++)
            _row(
              liveLineLabel(line),
              () => Navigator.pop<_LiveSelection>(context, (
                quality: null,
                line: line,
              )),
              selected: line == widget.line,
            )
        else ...[
          for (final quality in widget.media.qualities)
            _row(
              widget.media.qualityLabels[quality] ?? '$quality',
              () => Navigator.pop<_LiveSelection>(context, (
                quality: quality,
                line: null,
              )),
              selected: !widget.automatic && quality == widget.media.quality,
            ),
          _row(
            '自动',
            () => Navigator.pop<_LiveSelection>(context, (
              quality: 0,
              line: null,
            )),
            selected: widget.automatic,
          ),
        ],
      ],
    ),
  );
}
