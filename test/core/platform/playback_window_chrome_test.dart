import 'package:bilisail/core/platform/playback_window_chrome.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('44px caption routes controls and drag to its own window', (
    tester,
  ) async {
    final window = _Window();
    var backs = 0;
    var closes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: PlaybackWindowChrome(
              window: window,
              onBack: () => backs++,
              onClose: () => closes++,
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('playback-window-caption')))
          .height,
      44,
    );
    for (final tooltip in ['返回上一视频', '最小化', '最大化', '关闭播放']) {
      expect(tester.getSize(find.byTooltip(tooltip)).height, 44);
      await tester.tap(find.byTooltip(tooltip));
    }
    expect(backs, 1);
    expect(closes, 1);
    expect(window.minimizes, 1);
    expect(window.maximizes, 1);
    window.updateWindowPresentation(
      maximized: true,
      minimized: false,
      fullScreen: false,
    );
    await tester.pump();
    expect(find.byTooltip('还原'), findsOneWidget);
    final drag = find.byKey(const ValueKey('playback-window-drag-region'));
    await tester.drag(drag, const Offset(50, 0));
    await tester.pumpAndSettle();
    expect(window.drags, 1);
    await tester.tap(drag);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(drag);
    await tester.pumpAndSettle();
    expect(window.maximizes, 2);
    expect(tester.takeException(), isNull);
  });
}

class _Window extends WindowService {
  var drags = 0;
  var minimizes = 0;
  var maximizes = 0;

  @override
  Future<void> startDraggingPlaybackWindow() async => drags++;

  @override
  Future<void> minimizePlaybackWindow() async => minimizes++;

  @override
  Future<void> togglePlaybackWindowMaximized() async => maximizes++;
}
