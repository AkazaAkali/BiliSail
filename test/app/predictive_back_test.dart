import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/workspace_tabs.dart';
import 'package:bilisail/core/presentation/page_back_scope.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/shared/ui/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/input_test_app.dart';
import '../support/system_back_gesture.dart';

void main() {
  for (final mode in WorkspaceNavigationMode.values) {
    for (final edge in SwipeEdge.values) {
      testWidgets(
        'predictive back cancels then commits once in $mode from $edge',
        (tester) async {
          final disposed = <String>[];
          final builds = <String, int>{};
          final router = _router(
            mode: mode,
            builder: (_, tab) => _PageProbe(
              key: ValueKey(tab.id),
              tab: tab,
              disposed: disposed,
              builds: builds,
            ),
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(InputTestApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          router.go('/history');
          await tester.pumpAndSettle();
          final current = tester.element(find.text('page /history'));
          final origin = tester.getTopLeft(find.text('page /history'));

          expect(
            await systemBackGesture(tester, 'startBackGesture', edge: edge),
            isTrue,
          );
          await tester.pump();
          expect(find.text('page /'), findsOneWidget);
          expect(
            WorkspaceActivity.isActive(tester.element(find.text('page /'))),
            isFalse,
          );
          final beforeTicks = Map.of(builds);
          for (final progress in [0.2, 0.4, 0.6]) {
            await systemBackGesture(
              tester,
              'updateBackGestureProgress',
              progress: progress,
              edge: edge,
            );
            await tester.pump();
          }
          expect(builds, beforeTicks);
          final moved = tester.getTopLeft(find.text('page /history'));
          expect(moved, isNot(origin));
          expect(router.routeInformationProvider.value.uri.path, '/history');
          expect(disposed, isEmpty);
          await systemBackGesture(tester, 'cancelBackGesture');
          await tester.pumpAndSettle();
          expect(tester.element(find.text('page /history')), same(current));
          expect(tester.getTopLeft(find.text('page /history')), origin);
          expect(find.text('page /'), findsNothing);
          expect(disposed, isEmpty);

          await systemBackGesture(tester, 'startBackGesture', edge: edge);
          await tester.pump();
          await systemBackGesture(
            tester,
            'updateBackGestureProgress',
            progress: 0.7,
            edge: edge,
          );
          await systemBackGesture(tester, 'commitBackGesture');
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/');
          expect(find.text('page /'), findsOneWidget);
          expect(
            disposed,
            mode == WorkspaceNavigationMode.dualTabs ? ['tab-1'] : isEmpty,
          );
          expect(find.text('退出哔帆？'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  }

  testWidgets(
    'media history preview does not replace the retained player before commit',
    (tester) async {
      final disposed = <String>[];
      final router = _router(
        builder: (_, tab) => _PageProbe(tab: tab, disposed: disposed),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go('/video/A');
      await tester.pumpAndSettle();
      router.go('/video/B');
      await tester.pumpAndSettle();
      final player = tester.element(find.text('page /video/B'));
      await systemBackGesture(tester, 'startBackGesture');
      await tester.pump();
      expect(find.text('返回 A'), findsOneWidget);
      expect(find.text('page /video/A'), findsNothing);
      expect(tester.element(find.text('page /video/B')), same(player));
      expect(disposed, isEmpty);
      await systemBackGesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/video/A');
      expect(disposed, isEmpty);
      await systemBackGesture(tester, 'startBackGesture');
      await tester.pump();
      await systemBackGesture(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/video/A');
      expect(disposed, isEmpty);
      await systemBackGesture(tester, 'startBackGesture');
      await systemBackGesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(disposed, ['tab-1']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('root exit, page-local Back and modals retain their priority', (
    tester,
  ) async {
    final localBack = ValueNotifier(true);
    addTearDown(localBack.dispose);
    final router = _router(
      builder: (_, tab) => ValueListenableBuilder(
        valueListenable: localBack,
        builder: (_, enabled, _) => PageBackHandler(
          enabled: !tab.isRoot && enabled,
          onBack: () {
            localBack.value = false;
            return true;
          },
          child: Text('page ${tab.location.path}'),
        ),
      ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(InputTestApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(await systemBackGesture(tester, 'startBackGesture'), isFalse);
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('退出哔帆？'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    router.go('/history');
    await tester.pumpAndSettle();
    expect(await systemBackGesture(tester, 'startBackGesture'), isFalse);
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(localBack.value, isFalse);
    expect(router.routeInformationProvider.value.uri.path, '/history');
    final dialog = showAppDialog<void>(
      context: tester.element(find.text('page /history')),
      builder: (_) => const AlertDialog(content: Text('modal')),
    );
    await tester.pumpAndSettle();
    expect(await systemBackGesture(tester, 'startBackGesture'), isFalse);
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    await dialog;
    expect(find.text('modal'), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/history');
    final fullscreen = Navigator.of(tester.element(find.text('page /history')))
        .push<void>(
          RawDialogRoute<void>(
            barrierDismissible: false,
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) =>
                const Dialog.fullscreen(child: Text('fullscreen')),
          ),
        );
    await tester.pumpAndSettle();
    expect(await systemBackGesture(tester, 'startBackGesture'), isFalse);
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    await fullscreen;
    expect(find.text('fullscreen'), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/history');
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final interrupt in ['route', 'modal', 'keyboard']) {
    testWidgets('$interrupt change invalidates a pending gesture', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(InputTestApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go('/history');
      await tester.pumpAndSettle();
      await systemBackGesture(tester, 'startBackGesture');
      await tester.pump();
      await systemBackGesture(
        tester,
        'updateBackGestureProgress',
        progress: 0.5,
      );
      await tester.pump();
      if (interrupt == 'route') {
        router.go('/user/42');
      } else if (interrupt == 'modal') {
        showAppDialog<void>(
          context: tester.element(find.text('page /history')),
          builder: (_) => const AlertDialog(content: Text('new modal')),
        );
      } else {
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
      }
      await tester.pumpAndSettle();
      await systemBackGesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        interrupt == 'route' ? '/user/42' : '/history',
      );
      if (interrupt == 'modal') expect(find.text('new modal'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
  testWidgets('reduced animation keeps geometry and commits Back', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(InputTestApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    router.go('/history');
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.text('page /history'));
    await systemBackGesture(tester, 'startBackGesture');
    await systemBackGesture(tester, 'updateBackGestureProgress', progress: 0.7);
    await tester.pump();
    expect(tester.getRect(find.text('page /history')), rect);
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('navigation during completion discards the old commit', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(InputTestApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    router.go('/history');
    await tester.pumpAndSettle();
    await systemBackGesture(tester, 'startBackGesture');
    await tester.pump();
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pump(const Duration(milliseconds: 40));
    router.go('/user/42');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/user/42');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

GoRouter _router({
  WorkspaceNavigationMode mode = WorkspaceNavigationMode.dualTabs,
  WorkspacePageBuilder? builder,
}) => GoRouter(
  observers: [],
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
        for (final path in ['/', '/history', '/user/:mid', '/video/:bvid'])
          GoRoute(path: path, builder: (_, _) => const SizedBox.shrink()),
      ],
    ),
  ],
);

class _PageProbe extends StatefulWidget {
  const _PageProbe({
    super.key,
    required this.tab,
    required this.disposed,
    this.builds,
  });
  final WorkspaceTab tab;
  final List<String> disposed;
  final Map<String, int>? builds;

  @override
  State<_PageProbe> createState() => _PageProbeState();
}

class _PageProbeState extends State<_PageProbe> {
  @override
  Widget build(BuildContext context) {
    final builds = widget.builds;
    if (builds != null) {
      builds.update(widget.tab.id, (n) => n + 1, ifAbsent: () => 1);
    }
    return ColoredBox(
      color: Colors.white,
      child: Center(child: Text('page ${widget.tab.location.path}')),
    );
  }

  @override
  void dispose() {
    widget.disposed.add(widget.tab.id);
    super.dispose();
  }
}
