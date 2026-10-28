import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('VOD pause paints the settled scrolling position once', (
    tester,
  ) async {
    final scene = _Scene(live: false);
    addTearDown(scene.dispose);
    scene.add(DanmakuMode.scroll);
    await scene.mount(tester);
    final paints = scene.paints;
    scene.now += const Duration(milliseconds: 50);
    scene.vod.sync(
      confirmedPosition: scene.now,
      playing: false,
      buffering: false,
      seeking: false,
      rate: 1,
    );
    await tester.pump();
    expect(scene.paints, paints + 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final live in [false, true]) {
    final kind = live ? 'live' : 'VOD';
    testWidgets('$kind crossing a deadline while scheduling still wakes', (
      tester,
    ) async {
      var now = Duration.zero;
      var advanceOnRead = false;
      var armOnNotification = false;
      const deadline = Duration(milliseconds: 500);
      Duration readTime() {
        final sampled = now;
        if (advanceOnRead) {
          advanceOnRead = false;
          now = deadline;
        }
        return sampled;
      }

      final vod = DanmakuController(
        monotonicNow: readTime,
        maxAdmissionsPerFrame: 1,
      );
      final stream = LiveDanmakuController(
        monotonicNow: readTime,
        maxAdmissionsPerFrame: 1,
      );
      addTearDown(vod.dispose);
      addTearDown(stream.dispose);
      final controller = live ? stream : vod;
      controller.addListener(() {
        if (armOnNotification) {
          armOnNotification = false;
          advanceOnRead = true;
        }
      });
      void sync() => vod.sync(
        confirmedPosition: now,
        playing: true,
        buffering: false,
        seeking: false,
        rate: 1,
      );
      if (live) {
        stream.configure(area: 1, speed: 1, maxPerSecond: 0, offset: deadline);
        stream.add(const [
          LiveDanmakuEvent(id: 'top', text: 'top', mode: DanmakuMode.top),
          LiveDanmakuEvent(
            id: 'bottom',
            text: 'bottom',
            mode: DanmakuMode.bottom,
          ),
        ]);
      } else {
        vod.replaceEvents(const [
          DanmakuEvent(
            id: 'top',
            at: deadline,
            text: 'top',
            mode: DanmakuMode.top,
          ),
          DanmakuEvent(
            id: 'bottom',
            at: deadline,
            text: 'bottom',
            mode: DanmakuMode.bottom,
          ),
        ]);
        sync();
      }
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: live
              ? LiveDanmakuOverlay(controller: stream)
              : DanmakuOverlay(controller: vod),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      now = deadline - const Duration(microseconds: 1);
      armOnNotification = true;
      if (live) {
        stream.add(const []);
      } else {
        sync();
      }
      // The monotonic deadline crosses during the notification. No later
      // playback confirmation, arrival or timer advance should be required.
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(live ? stream.visibleCount : vod.visibleCount, 2);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      '$kind muted overlays cancel deadline wakes and catch up on return',
      (tester) async {
        final scene = _Scene(live: live);
        addTearDown(scene.dispose);
        scene.add(DanmakuMode.top);
        await scene.mount(tester);
        await scene.mount(tester, enabled: false);
        final paints = scene.paints;
        await scene.advance(tester, const Duration(milliseconds: 500));
        expect(scene.paints, paints);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await scene.mount(tester);
        expect(scene.visible, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets('$kind fixed text idles and clears at its deadline', (
      tester,
    ) async {
      final scene = _Scene(live: live);
      addTearDown(scene.dispose);
      scene.add(DanmakuMode.top);
      scene.add(DanmakuMode.bottom);
      await scene.mount(tester);
      expect(scene.visible, 2);
      expect(tester.binding.hasScheduledFrame, isFalse);
      final paints = scene.paints;
      await scene.advance(tester, const Duration(milliseconds: 200));
      scene.sync();
      await tester.pump();
      expect(scene.paints, paints, reason: 'unchanged clocks do not repaint');
      expect(tester.binding.hasScheduledFrame, isFalse);
      await scene.advance(tester, const Duration(milliseconds: 200));
      expect(scene.visible, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      '$kind mixed text keeps scrolling then idles until fixed expiry',
      (tester) async {
        final scene = _Scene(live: live);
        addTearDown(scene.dispose);
        scene.add(DanmakuMode.top);
        scene.add(DanmakuMode.scroll);
        await scene.mount(tester);
        expect(tester.binding.hasScheduledFrame, isTrue);
        final paints = scene.paints;
        await scene.advance(tester, const Duration(milliseconds: 100));
        expect(scene.paints, greaterThan(paints));
        await scene.advance(tester, const Duration(milliseconds: 100));
        expect(scene.visible, 1);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await scene.advance(tester, const Duration(milliseconds: 200));
        expect(scene.visible, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('$kind fixed text clears immediately when removed', (
      tester,
    ) async {
      final scene = _Scene(live: live);
      addTearDown(scene.dispose);
      scene.add(DanmakuMode.top);
      await scene.mount(tester);
      expect(scene.visible, 1);
      scene.clear();
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      await tester.pump();
      expect(scene.visible, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      '$kind pending timer survives resize and is cancelled on swap',
      (tester) async {
        final scene = _Scene(live: live);
        final replacement = _Scene(live: live);
        addTearDown(scene.dispose);
        addTearDown(replacement.dispose);
        scene.add(DanmakuMode.bottom);
        await scene.mount(tester);
        final paints = scene.paints;
        await scene.mount(tester, width: 500);
        expect(scene.paints, greaterThan(paints));
        expect(scene.visible, 1);
        await replacement.mount(tester, width: 500);
        final replacementPaints = replacement.paints;
        await scene.advance(tester, const Duration(seconds: 1));
        expect(replacement.paints, replacementPaints);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'VOD fixed expiry freezes on pause and resumes independently of rate',
    (tester) async {
      final scene = _Scene(live: false);
      addTearDown(scene.dispose);
      scene.add(DanmakuMode.top);
      await scene.mount(tester);
      await scene.advance(tester, const Duration(milliseconds: 100));
      scene.vod.sync(
        confirmedPosition: scene.now,
        playing: false,
        buffering: false,
        seeking: false,
        rate: 3,
      );
      await scene.advance(tester, const Duration(seconds: 2));
      expect(scene.visible, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      scene.vod.sync(
        confirmedPosition: const Duration(milliseconds: 100),
        playing: true,
        buffering: false,
        seeking: false,
        rate: 3,
      );
      await scene.advance(tester, const Duration(milliseconds: 299));
      expect(scene.visible, 1);
      await scene.advance(tester, const Duration(milliseconds: 1));
      expect(scene.visible, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'VOD fixed expiry waits for confirmation past interpolation limit',
    (tester) async {
      var now = Duration.zero;
      final controller = DanmakuController(
        monotonicNow: () => now,
        fixedDuration: const Duration(seconds: 1),
      );
      addTearDown(controller.dispose);
      controller.replaceEvents(const [
        DanmakuEvent(
          id: 'a',
          at: Duration.zero,
          text: 'fixed',
          mode: DanmakuMode.top,
        ),
      ]);
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
          child: DanmakuOverlay(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pump();
      now = const Duration(seconds: 2);
      await tester.pump(now);
      expect(controller.visibleCount, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      sync();
      now += const Duration(milliseconds: 300);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(controller.visibleCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'live delayed arrivals sleep, admit in bounded frames, and expire',
    (tester) async {
      final scene = _Scene(live: true);
      addTearDown(scene.dispose);
      scene.stream.configure(
        area: 1,
        speed: 1,
        maxPerSecond: 0,
        offset: const Duration(seconds: 1),
      );
      scene.add(DanmakuMode.top);
      scene.add(DanmakuMode.bottom);
      await scene.mount(tester);
      expect(scene.visible, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await scene.advance(tester, const Duration(milliseconds: 999));
      expect(scene.visible, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await scene.advance(tester, const Duration(milliseconds: 1));
      expect(scene.visible, 2);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await scene.advance(tester, const Duration(milliseconds: 400));
      expect(scene.visible, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final class _Scene {
  _Scene({required this.live});
  final bool live;
  Duration now = Duration.zero;
  final events = <DanmakuEvent>[];
  late final vod = DanmakuController(
    monotonicNow: () => now,
    fixedDuration: const Duration(milliseconds: 400),
    scrollDuration: const Duration(milliseconds: 200),
    maxAdmissionsPerFrame: 1,
  );
  late final stream = LiveDanmakuController(
    monotonicNow: () => now,
    fixedDuration: const Duration(milliseconds: 400),
    scrollDuration: const Duration(milliseconds: 200),
    maxAdmissionsPerFrame: 1,
  );
  int get visible => live ? stream.visibleCount : vod.visibleCount;
  int get paints =>
      (live ? stream.rasterStatistics : vod.rasterStatistics).totalPaints;

  void add(DanmakuMode mode) {
    final id = '${events.length}';
    events.add(DanmakuEvent(id: id, at: now, text: 'comment $id', mode: mode));
    if (live) {
      stream.add([LiveDanmakuEvent(id: id, text: 'comment $id', mode: mode)]);
    } else {
      vod.replaceEvents(events);
      sync();
    }
  }

  void sync() {
    if (live) return;
    vod.sync(
      confirmedPosition: now,
      playing: true,
      buffering: false,
      seeking: false,
      rate: 1,
    );
  }

  void clear() => live ? stream.clear() : vod.replaceEvents(const []);

  Future<void> mount(
    WidgetTester tester, {
    double width = 800,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: width,
            height: 400,
            child: TickerMode(
              enabled: enabled,
              child: live
                  ? LiveDanmakuOverlay(controller: stream, bottomInset: 0)
                  : DanmakuOverlay(controller: vod),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> advance(WidgetTester tester, Duration elapsed) async {
    now += elapsed;
    await tester.pump(elapsed);
    await tester.pump();
    await tester.pump();
  }

  void dispose() {
    if (live) {
      stream.dispose();
    } else {
      vod.dispose();
    }
  }
}
