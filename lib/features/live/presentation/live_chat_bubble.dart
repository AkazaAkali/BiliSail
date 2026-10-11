import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/user.dart';
import '../../../shared/ui/app_network_image.dart';
import '../domain/live_room.dart';
import '../domain/live_chat_content.dart';

class LiveChatBubble extends StatefulWidget {
  const LiveChatBubble({
    super.key,
    required this.message,
    this.onOpenUser,
    this.content,
  });
  final LiveChatMessage message;
  final ValueChanged<UserId>? onOpenUser;
  final LiveChatContent? content;

  @override
  State<LiveChatBubble> createState() => _LiveChatBubbleState();
}

class _LiveChatBubbleState extends State<LiveChatBubble> {
  late LiveChatContent _content;

  @override
  void initState() {
    super.initState();
    _content = widget.content ?? LiveChatContent(widget.message);
  }

  @override
  void didUpdateWidget(covariant LiveChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final content = widget.content;
    if (content != null) {
      _content = content;
    } else if (!_content.matches(widget.message)) {
      _content = LiveChatContent(widget.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final theme = Theme.of(context);
    final userId = message.userId;
    final open = userId != null && userId.isValid && widget.onOpenUser != null
        ? () => widget.onOpenUser?.call(userId)
        : null;
    final name = Text(
      message.userName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: open == null
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.primary,
      ),
    );
    final spans = <InlineSpan>[
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: open == null
              ? name
              : Semantics(
                  button: true,
                  child: InkWell(onTap: open, child: name),
                ),
        ),
      ),
      const TextSpan(text: ': '),
    ];
    for (final part in _content.parts) {
      final image = part.image;
      spans.add(
        image == null
            ? TextSpan(text: part.text)
            : _image(context, image, part.text, sticker: part.sticker),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text.rich(TextSpan(children: spans)),
      ),
    );
  }

  WidgetSpan _image(
    BuildContext context,
    LiveChatImage image,
    String label, {
    bool sticker = false,
  }) {
    final limit = sticker
        ? 80.0
        : MediaQuery.textScalerOf(context).scale(24).clamp(24.0, 48.0);
    final longest = math.max(1, math.max(image.width, image.height));
    final width = (limit * image.width / longest).clamp(1.0, limit);
    final height = (limit * image.height / longest).clamp(1.0, limit);
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: AppNetworkImage(
        url: image.url.toString(),
        width: width,
        height: height,
        fit: BoxFit.contain,
        cacheWidth: (width * 3).ceil(),
        semanticLabel: label,
        errorBuilder: (_, _, _) => SizedBox(
          width: sticker ? width : null,
          child: Text(
            label,
            maxLines: sticker ? 2 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
