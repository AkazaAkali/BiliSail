import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:bilisail/shared/ui/compact_phone_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'compact spacing excludes desktop, tablets and enlarged text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.display.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.view.display.reset);
      Future<bool> compact({
        double displayWidth = 390,
        double scale = 1,
        List<DisplayFeature> features = const [],
      }) async {
        tester.view.display.size = Size(displayWidth, 844);
        var result = false;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 844),
                textScaler: TextScaler.linear(scale),
                displayFeatures: features,
              ),
              child: Builder(
                builder: (context) {
                  result = useCompactPhoneSpacing(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
        return result;
      }

      final mobile =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
      expect(await compact(), mobile);
      expect(await compact(displayWidth: 800), isFalse);
      expect(await compact(scale: 2), isFalse);
      for (final type in [
        DisplayFeatureType.cutout,
        DisplayFeatureType.fold,
        DisplayFeatureType.hinge,
      ]) {
        expect(
          await compact(
            features: [
              DisplayFeature(
                bounds: const Rect.fromLTWH(180, 0, 30, 24),
                type: type,
                state: DisplayFeatureState.unknown,
              ),
            ],
          ),
          type == DisplayFeatureType.cutout && mobile,
          reason: 'A camera cutout is not a fold or hinge: $type',
        );
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );
}
