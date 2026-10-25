import 'package:flutter/material.dart';

import 'window_service.dart';

class PlaybackWindowChrome extends StatelessWidget {
  const PlaybackWindowChrome({
    super.key,
    required this.window,
    required this.onBack,
    required this.onClose,
  });

  final WindowService window;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('playback-window-caption'),
    height: 44,
    child: Row(
      children: [
        _button('返回上一视频', Icons.arrow_back_rounded, onBack),
        Expanded(
          child: GestureDetector(
            key: const ValueKey('playback-window-drag-region'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => window.startDraggingPlaybackWindow(),
            onDoubleTap: window.togglePlaybackWindowMaximized,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '哔帆 · 播放',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
        ),
        _button('最小化', Icons.remove_rounded, window.minimizePlaybackWindow),
        ValueListenableBuilder<bool>(
          valueListenable: window.maximized,
          builder: (context, maximized, _) => _button(
            maximized ? '还原' : '最大化',
            maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
            window.togglePlaybackWindowMaximized,
          ),
        ),
        _button('关闭播放', Icons.close_rounded, onClose, close: true),
      ],
    ),
  );

  Widget _button(
    String tooltip,
    IconData icon,
    VoidCallback onPressed, {
    bool close = false,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    style: ButtonStyle(
      fixedSize: const WidgetStatePropertyAll(Size(46, 44)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      backgroundColor: close
          ? WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.hovered)
                  ? const Color(0xffc42b1c)
                  : null,
            )
          : null,
      foregroundColor: close
          ? WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.hovered) ? Colors.white : null,
            )
          : null,
    ),
  );
}
