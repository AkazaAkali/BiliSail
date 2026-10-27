import 'package:bilisail/app/shell.dart';
import 'package:bilisail/core/presentation/page_back_scope.dart';
import 'package:bilisail/features/playback/presentation/playback_timeline_bar.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/input_test_app.dart';

void main() {
  for (final mode in WorkspaceNavigationMode.values) {
    testWidgets('macOS back follows page and video history in $mode', (
      tester,
    ) async {
      final router = _router(mode: mode);
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      router.go('/video/A');
      await tester.pumpAndSettle();
      final firstVideo = tester.element(find.text('page /video/A'));
      router.go('/video/B');
      await tester.pumpAndSettle();
      final drag = await _drag(tester);
      await drag.moveBy(const Offset(150, 0));
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, '/video/B');
      await drag.panZoomEnd();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/video/A');
      expect(tester.element(find.text('page /video/A')), same(firstVideo));

      router.go('/user/42');
      await tester.pumpAndSettle();
      await _back(tester);
      expect(
        router.routeInformationProvider.value.uri.path,
        mode == WorkspaceNavigationMode.dualTabs ? '/' : '/video/A',
      );
      expect(
        tester.element(find.text('page /video/A', skipOffstage: false)),
        same(firstVideo),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('page-local Back wins before the workspace page changes', (
    tester,
  ) async {
    var detail = true;
    final router = _router(
      builder: (_, tab) => StatefulBuilder(
        builder: (context, setState) => PageBackHandler(
          enabled: tab.isProfile && detail,
          onBack: () {
            setState(() => detail = false);
            return true;
          },
          child: Text('page ${tab.location.path}'),
        ),
      ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    router.go('/user/42');
    await tester.pumpAndSettle();
    await _back(tester);
    expect(detail, isFalse);
    expect(router.routeInformationProvider.value.uri.path, '/user/42');
    await _back(tester);
    expect(router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets('empty root history and route changes do not navigate', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    await _back(tester);
    expect(router.routeInformationProvider.value.uri.path, '/');
    router.go('/video/A');
    await tester.pumpAndSettle();
    final drag = await _drag(tester);
    await drag.moveBy(const Offset(150, 0));
    await tester.pump();
    router.go('/user/42');
    await tester.pumpAndSettle();
    await drag.panZoomEnd();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/user/42');
    expect(tester.takeException(), isNull);
  });

  testWidgets('player timeline keeps mouse seek and blocks trackpad Back', (
    tester,
  ) async {
    final seeks = <Duration>[];
    final bounds = GlobalKey();
    final router = _router(
      builder: (_, tab) => tab.isPlayback
          ? SizedBox.expand(
              key: bounds,
              child: Center(
                child: PlaybackTimelineBar(
                  position: const Duration(seconds: 30),
                  duration: const Duration(minutes: 1),
                  buffered: const Duration(seconds: 50),
                  chapters: const [],
                  sourceGeneration: 1,
                  playerBoundsKey: bounds,
                  onSeek: seeks.add,
                  onPreviewRequest: () {},
                ),
              ),
            )
          : const SizedBox.expand(),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router));
    router.go('/video/A');
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('playback-timeline-slider'));
    final origin = tester.getCenter(slider);
    final trackpad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await trackpad.panZoomStart(origin);
    await trackpad.moveBy(const Offset(60, 0));
    await trackpad.moveBy(const Offset(140, 0));
    await trackpad.panZoomEnd();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/video/A');
    expect(seeks, isEmpty);
    final mouse = await tester.startGesture(
      origin,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(100, 0));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(seeks, hasLength(1));
    expect(seeks.single, greaterThan(const Duration(seconds: 30)));
    expect(router.routeInformationProvider.value.uri.path, '/video/A');
    expect(tester.takeException(), isNull);
  });
}

Future<TestGesture> _drag(WidgetTester tester) async {
  final drag = await tester.createGesture(kind: PointerDeviceKind.trackpad);
  // Start in page content, away from the shell's horizontal tab strips.
  await drag.panZoomStart(const Offset(400, 350));
  return drag;
}

Future<void> _back(WidgetTester tester) async {
  final drag = await _drag(tester);
  await drag.moveBy(const Offset(60, 0));
  await drag.moveBy(const Offset(90, 0));
  await drag.panZoomEnd();
  await tester.pumpAndSettle();
}

Widget _app(GoRouter router) => InputTestApp.router(
  routerConfig: router,
  theme: ThemeData(platform: TargetPlatform.macOS),
);

GoRouter _router({
  WorkspaceNavigationMode mode = WorkspaceNavigationMode.singlePage,
  WorkspacePageBuilder? builder,
}) => GoRouter(
  routes: [
    ShellRoute(
      observers: [],
      builder: (context, state, child) => BiliAppShell(
        location: state.uri.toString(),
        navigationMode: mode,
        pageBuilder: builder ?? (_, tab) => Text('page ${tab.location.path}'),
        child: child,
      ),
      routes: [
        for (final path in ['/', '/video/:id', '/user/:id'])
          GoRoute(path: path, builder: (_, _) => const SizedBox.shrink()),
      ],
    ),
  ],
);
