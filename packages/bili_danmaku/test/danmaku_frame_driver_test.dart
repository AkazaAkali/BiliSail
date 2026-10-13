import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final isLive in [false, true]) {
    for (final mode in DanmakuMode.values) {
      testWidgets(
        '${isLive ? 'live' : 'VOD'} $mode bounds refresh on 180Hz display',
        (tester) async {
          var now = Duration.zero;
          final vod = DanmakuController(monotonicNow: () => now);
          final live = LiveDanmakuController(monotonicNow: () => now);
          addTearDown(vod.dispose);
          addTearDown(live.dispose);
          void sync() => vod.sync(
            confirmedPosition: now,
            playing: true,
            buffering: false,
            seeking: false,
            rate: 1,
          );
          sync();
          vod.replaceEvents([
            DanmakuEvent(
              id: 'a',
              at: Duration.zero,
              text: 'visible',
              mode: mode,
            ),
          ]);
          live.add([LiveDanmakuEvent(id: 'a', text: 'visible', mode: mode)]);
          final overlay = isLive
              ? LiveDanmakuOverlay(controller: live)
              : DanmakuOverlay(controller: vod);
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: SizedBox(width: 800, height: 400, child: overlay),
              ),
            ),
          );
          await tester.pump();
          int paints() => isLive
              ? live.rasterStatistics.imagePaints
              : vod.rasterStatistics.imagePaints;
          final initial = paints();
          expect(initial, greaterThan(0));
          for (var i = 0; i < 180; i++) {
            now += const Duration(microseconds: 5556);
            if (i % 18 == 0) sync();
            await tester.pump(const Duration(microseconds: 5556));
          }
          if (mode == DanmakuMode.scroll) {
            expect(paints() - initial, inInclusiveRange(55, 60));
            final x = isLive ? live.frame().single.x : vod.frame().single.x;
            expect(x, lessThan(750));
          } else {
            // Confirmed clock samples and monitor vsync do not repaint fixed text.
            expect(paints(), initial);
            expect(tester.binding.hasScheduledFrame, isFalse);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets(
      '${isLive ? 'live' : 'VOD'} fixed expiry clears and future scroll wakes once',
      (tester) async {
        var now = Duration.zero;
        final vod = DanmakuController(monotonicNow: () => now);
        final live = LiveDanmakuController(monotonicNow: () => now);
        addTearDown(vod.dispose);
        addTearDown(live.dispose);
        void sync() => vod.sync(
          confirmedPosition: now,
          playing: true,
          buffering: false,
          seeking: false,
          rate: 1,
        );
        sync();
        vod.replaceEvents(const [
          DanmakuEvent(
            id: 'fixed',
            at: Duration.zero,
            text: 'fixed',
            mode: DanmakuMode.top,
          ),
          DanmakuEvent(
            id: 'future',
            at: Duration(milliseconds: 4300),
            text: 'scroll',
          ),
        ]);
        live.add(const [
          LiveDanmakuEvent(id: 'fixed', text: 'fixed', mode: DanmakuMode.top),
        ]);
        final overlay = isLive
            ? LiveDanmakuOverlay(controller: live)
            : DanmakuOverlay(controller: vod);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(width: 800, height: 400, child: overlay),
            ),
          ),
        );
        await tester.pump();
        for (var i = 0; i < 8; i++) {
          now += const Duration(milliseconds: 500);
          sync();
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(isLive ? live.visibleCount : vod.visibleCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
        if (isLive) {
          live.configure(
            area: .75,
            speed: 1,
            maxPerSecond: 20,
            offset: const Duration(milliseconds: 300),
          );
          live.add(const [LiveDanmakuEvent(id: 'future', text: 'scroll')]);
        }
        now += const Duration(milliseconds: 300);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(isLive ? live.visibleCount : vod.visibleCount, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '${isLive ? 'live' : 'VOD'} TickerMode suspends timers and resumes current clock',
      (tester) async {
        var now = Duration.zero;
        final vod = DanmakuController(monotonicNow: () => now);
        final live = LiveDanmakuController(monotonicNow: () => now);
        addTearDown(vod.dispose);
        addTearDown(live.dispose);
        void sync() => vod.sync(
          confirmedPosition: now,
          playing: true,
          buffering: false,
          seeking: false,
          rate: 1,
        );
        sync();
        vod.replaceEvents(const [
          DanmakuEvent(id: 'a', at: Duration.zero, text: 'visible'),
        ]);
        live.add(const [LiveDanmakuEvent(id: 'a', text: 'visible')]);
        final overlay = isLive
            ? LiveDanmakuOverlay(controller: live)
            : DanmakuOverlay(controller: vod);
        Future<void> show(bool active) => tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: TickerMode(
              enabled: active,
              child: Center(
                child: SizedBox(width: 800, height: 400, child: overlay),
              ),
            ),
          ),
        );
        await show(true);
        await tester.pump();
        await show(false);
        final paints = isLive
            ? live.rasterStatistics.imagePaints
            : vod.rasterStatistics.imagePaints;
        now = const Duration(seconds: 1);
        sync();
        await tester.pump(const Duration(seconds: 1));
        expect(
          isLive
              ? live.rasterStatistics.imagePaints
              : vod.rasterStatistics.imagePaints,
          paints,
        );
        await show(true);
        await tester.pump();
        expect(
          isLive
              ? live.rasterStatistics.imagePaints
              : vod.rasterStatistics.imagePaints,
          greaterThan(paints),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
