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
      }) async {
        tester.view.display.size = Size(displayWidth, 844);
        var result = false;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 844),
                textScaler: TextScaler.linear(scale),
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
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );
}
