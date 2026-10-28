import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Identify phone layouts without treating narrow desktop/tablet panes as phones.
/// Visual grouping uses this independently of accessibility text scaling.
bool isCompactPhoneLayout(BuildContext context) {
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return false;
  }
  final display = View.of(context).display;
  final media = MediaQuery.of(context);
  return display.size.shortestSide / display.devicePixelRatio < 600 &&
      media.size.width < 600 &&
      media.displayFeatures.isEmpty;
}

/// Tighten decorative gaps only when accessibility text has room to breathe.
bool useCompactPhoneSpacing(BuildContext context) =>
    isCompactPhoneLayout(context) &&
    MediaQuery.textScalerOf(context).scale(14) <= 18;
