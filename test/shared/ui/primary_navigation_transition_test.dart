import 'package:bilisail/shared/ui/primary_navigation_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'primary motion retains its child and only composites per frame',
    (tester) async {
      final index = ValueNotifier<int?>(0);
      addTearDown(index.dispose);
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: index,
            builder: (context, value, child) => PrimaryNavigationTransition(
              index: value,
              enabled: true,
              child: child!,
            ),
            child: Builder(
              builder: (_) {
                builds++;
                return const Text('retained');
              },
            ),
          ),
        ),
      );
      Finder within(Type type) => find.descendant(
        of: find.byType(PrimaryNavigationTransition),
        matching: find.byType(type),
      );
      Offset slide() => tester
          .widget<SlideTransition>(within(SlideTransition))
          .position
          .value;
      // Image-heavy pages keep an opaque composition throughout the slide.
      expect(within(FadeTransition), findsNothing);
      final element = tester.element(find.text('retained'));
      expect(slide(), Offset.zero);
      index.value = 2;
      await tester.pump();
      expect(slide().dx, greaterThan(0));
      final start = slide().dx;
      await tester.pump(const Duration(milliseconds: 50));
      expect(slide().dx, inExclusiveRange(0, start));
      expect(builds, 1);
      // Retarget while still moving; the last tap owns the direction and state.
      index.value = 1;
      await tester.pump();
      expect(slide().dx, lessThan(0));
      await tester.pumpAndSettle();
      expect(slide(), Offset.zero);
      expect(tester.element(find.text('retained')), same(element));
      expect(builds, 1);
      // Entering/leaving detail pages must cancel primary motion.
      index.value = 3;
      await tester.pump();
      index.value = null;
      await tester.pump();
      expect(slide(), Offset.zero);
      index.value = 0;
      await tester.pump();
      expect(slide(), Offset.zero);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('disabled motion and accessibility changes settle immediately', (
    tester,
  ) async {
    final reduceMotion = ValueNotifier(false);
    final enabled = ValueNotifier(true);
    final index = ValueNotifier(0);
    addTearDown(reduceMotion.dispose);
    addTearDown(enabled.dispose);
    addTearDown(index.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: Listenable.merge([reduceMotion, enabled, index]),
          builder: (context, _) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion.value),
            child: PrimaryNavigationTransition(
              index: index.value,
              enabled: enabled.value,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    Offset slide() => tester
        .widget<SlideTransition>(
          find.descendant(
            of: find.byType(PrimaryNavigationTransition),
            matching: find.byType(SlideTransition),
          ),
        )
        .position
        .value;
    index.value = 1;
    await tester.pump();
    expect(slide().dx, greaterThan(0));
    reduceMotion.value = true;
    await tester.pumpAndSettle();
    expect(slide(), Offset.zero);
    index.value = 2;
    await tester.pump();
    expect(slide(), Offset.zero);
    reduceMotion.value = false;
    enabled.value = false;
    index.value = 3;
    await tester.pump();
    expect(slide(), Offset.zero);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
