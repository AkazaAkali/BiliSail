import 'package:flutter/material.dart';

const desktopCaptionHeight = 44.0;
const desktopCaptionTextStyle = TextStyle(fontSize: 13);

class DesktopCaptionButton extends StatelessWidget {
  const DesktopCaptionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.close = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool close;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    style: ButtonStyle(
      fixedSize: const WidgetStatePropertyAll(Size(46, desktopCaptionHeight)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
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
