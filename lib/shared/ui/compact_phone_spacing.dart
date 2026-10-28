import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Tighten decorative gaps only on phones, not narrow desktop/tablet windows.
/// Keep the roomier layout when accessibility text needs additional space.
bool useCompactPhoneSpacing(BuildContext context) {
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return false;
  }
  final display = View.of(context).display;
  final media = MediaQuery.of(context);
  return display.size.shortestSide / display.devicePixelRatio < 600 &&
      media.size.width < 600 &&
      media.displayFeatures.isEmpty &&
      media.textScaler.scale(14) <= 18;
}
