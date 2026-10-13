import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty and future-only overlays stop scheduling frames', (
    tester,
  ) async {
    var now = Duration.zero;
    final controller = DanmakuController(monotonicNow: () => now);
    addTearDown(controller.dispose);
    void sync() => controller.sync(
      confirmedPosition: now,
      playing: true,
      buffering: false,
      seeking: false,
      rate: 1,
    );
    sync();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 400,
          child: DanmakuOverlay(controller: controller),
        ),
      ),
    );
    await tester.pump();
    expect(controller.needsFrame, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    for (var tick = 1; tick <= 5; tick++) {
      now = Duration(milliseconds: tick * 100);
      sync();
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    controller.replaceEvents(const [
      DanmakuEvent(id: 'future', at: Duration(seconds: 1), text: 'arrived'),
    ]);
    await tester.pump();
    expect(controller.needsFrame, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    now = const Duration(seconds: 1);
    sync();
    await tester.pump();
    expect(controller.visibleCount, 1);
    expect(controller.needsFrame, isTrue);
    // Animation waits for its bounded timer rather than requesting every vsync.
    expect(tester.binding.hasScheduledFrame, isFalse);
    final paints = controller.rasterStatistics.imagePaints;
    now += const Duration(milliseconds: 17);
    await tester.pump(const Duration(milliseconds: 17));
    expect(controller.rasterStatistics.imagePaints, greaterThan(paints));
    controller.replaceEvents(const []);
    await tester.pump();
    expect(controller.visibleCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('future arrivals wake between confirmed position samples', (
    tester,
  ) async {
    var now = Duration.zero;
    final controller = DanmakuController(monotonicNow: () => now);
    addTearDown(controller.dispose);
    controller.replaceEvents(const [
      DanmakuEvent(id: 'future', at: Duration(milliseconds: 300), text: 'due'),
    ]);
    controller.sync(
      confirmedPosition: Duration.zero,
      playing: true,
      buffering: false,
      seeking: false,
      rate: 2,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 400,
          child: DanmakuOverlay(controller: controller),
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    now = const Duration(milliseconds: 150);
    await tester.pump(now);
    await tester.pump();
    expect(controller.visibleCount, 1);
    expect(controller.needsFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('a position discontinuity clears the last visible frame', () {
    var now = Duration.zero;
    final controller = DanmakuController(monotonicNow: () => now);
    addTearDown(controller.dispose);
    controller.setViewport(width: 800, height: 400);
    controller.replaceEvents(const [
      DanmakuEvent(id: 'visible', at: Duration.zero, text: 'visible'),
    ]);
    controller.frame();
    var notifications = 0;
    controller.addListener(() => notifications++);
    now = const Duration(seconds: 20);
    controller.sync(
      confirmedPosition: now,
      playing: true,
      buffering: false,
      seeking: false,
      rate: 2,
    );
    expect(notifications, 1);
    expect(controller.frame(), isEmpty);
    expect(controller.needsFrame, isFalse);
  });

  testWidgets('pausing cancels the pending arrival and resume reanchors it', (
    tester,
  ) async {
    var now = Duration.zero;
    final controller = DanmakuController(monotonicNow: () => now);
    addTearDown(controller.dispose);
    controller.replaceEvents(const [
      DanmakuEvent(id: 'future', at: Duration(milliseconds: 300), text: 'due'),
    ]);
    void sync(bool playing) => controller.sync(
      confirmedPosition: Duration.zero,
      playing: playing,
      buffering: false,
      seeking: false,
      rate: 1,
    );
    sync(true);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 400,
          child: DanmakuOverlay(controller: controller),
        ),
      ),
    );
    await tester.pump();
    sync(false);
    now = const Duration(milliseconds: 500);
    await tester.pump(now);
    expect(controller.visibleCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    sync(true);
    now += const Duration(milliseconds: 300);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(controller.visibleCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
