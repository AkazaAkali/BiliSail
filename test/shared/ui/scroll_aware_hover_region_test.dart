import 'package:bilisail/shared/ui/scroll_aware_hover_region.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final exitDuringScroll in [false, true]) {
    testWidgets('nested scrolling restores only the current pointer '
        '(exit=$exitDuringScroll)', (tester) async {
      final outer = ScrollController();
      final inner = ScrollController();
      final events = <bool>[];
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        outer.dispose();
        inner.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: outer,
              child: SizedBox(
                height: 1400,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 320,
                    height: 300,
                    child: SingleChildScrollView(
                      controller: inner,
                      child: ScrollAwareHoverRegion(
                        onHover: events.add,
                        child: const SizedBox(width: 320, height: 900),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(100, 100));
      addTearDown(mouse.removePointer);
      await tester.pump();
      expect(events, [true]);
      final movingOuter = outer.animateTo(
        20,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      final movingInner = inner.animateTo(
        20,
        duration: const Duration(milliseconds: 500),
        curve: Curves.linear,
      );
      await tester.pump();
      expect(events, [true, false]);
      await mouse.moveTo(const Offset(600, 400));
      if (!exitDuringScroll) await mouse.moveTo(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 220));
      await movingOuter;
      expect(outer.position.isScrollingNotifier.value, isFalse);
      expect(inner.position.isScrollingNotifier.value, isTrue);
      expect(events, [true, false]);
      await tester.pump(const Duration(milliseconds: 300));
      await movingInner;
      await tester.pump();
      expect(events, exitDuringScroll ? [true, false] : [true, false, true]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('removing a moving region releases scroll listeners', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var notifications = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: ScrollAwareHoverRegion(
              onHover: (_) => notifications++,
              child: const SizedBox(width: 320, height: 1400),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 100));
    await tester.pump();
    final moving = controller.animateTo(
      200,
      duration: const Duration(seconds: 1),
      curve: Curves.linear,
    );
    await tester.pump();
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    await moving;
    final before = notifications;
    await tester.pump(const Duration(seconds: 2));
    expect(notifications, before);
    expect(tester.takeException(), isNull);
  });
}
