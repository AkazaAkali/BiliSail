import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/app/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:bilisail/shared/ui/paging_tab_strip.dart';
import 'package:bilisail/shared/ui/playback_info_tabs.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'video phone tabs trim padding but retain typography and 48dp targets',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      tester.view.display.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.view.display.reset);
      var value = 0;
      var menuTaps = 0;
      Future<void> show({
        bool compact = true,
        double displayWidth = 390,
        double scale = 1,
      }) async {
        tester.view.display.size = Size(displayWidth, 700);
        await tester.pumpWidget(
          MaterialApp(
            theme: BiliTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 700),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, update) => PlaybackInfoTabs(
                    compactPhoneNavigation: compact,
                    labels: const [Text('简介'), Text('评论')],
                    value: value,
                    onChanged: (tab) => update(() => value = tab),
                    viewKey: const ValueKey('compact-info-pager'),
                    itemKey: (tab) => ValueKey('compact-info-tab-$tab'),
                    trailing: IconButton(
                      key: const ValueKey('compact-info-menu'),
                      onPressed: () => menuTaps++,
                      icon: const Icon(Icons.more_vert),
                    ),
                    pageBuilder: (_, tab, _) => Text('信息页$tab'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      final first = find.byKey(const ValueKey('compact-info-tab-0'));
      final second = find.byKey(const ValueKey('compact-info-tab-1'));
      final menu = find.byKey(const ValueKey('compact-info-menu'));
      await show(compact: false);
      final regularHeight = tester.getSize(first).height;
      final regularMenuHeight = tester.getSize(menu).height;
      final regularFont = tester
          .widget<RichText>(
            find.descendant(
              of: find.text('简介'),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.fontSize;
      await show();
      final phone =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
      expect(tester.getSize(first).height, phone ? 48 : regularHeight);
      expect(
        tester.getSize(menu).height,
        phone ? greaterThanOrEqualTo(48) : regularMenuHeight,
      );
      expect(
        tester
            .widget<RichText>(
              find.descendant(
                of: find.text('简介'),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style
            ?.fontSize,
        regularFont,
      );
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(value, 1);
      expect(find.text('信息页1').hitTestable(), findsOneWidget);
      await tester.tap(menu);
      expect(menuTaps, 1);
      await show(displayWidth: 800);
      expect(tester.getSize(first).height, regularHeight);
      await show(scale: 2);
      expect(tester.getSize(first).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );

  final pager = find.byKey(const ValueKey('playback-test-pager'));
  late StateSetter update;
  var value = 0;
  var active = true;
  var changes = 0;
  var visible = true;
  var slot = 0;

  Future<void> mount(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    value = 0;
    active = true;
    changes = 0;
    visible = true;
    slot = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return WorkspaceActivity(
                  active: active,
                  child: !visible
                      ? const SizedBox()
                      : PlaybackInfoTabs(
                          key: PageStorageKey('playback-slot-$slot'),
                          labels: const [Text('简介'), Text('评论')],
                          value: value,
                          onChanged: (tab) => setState(() {
                            value = tab;
                            changes++;
                          }),
                          viewKey: const ValueKey('playback-test-pager'),
                          pageBuilder: (_, tab, _) => ListView.builder(
                            key: PageStorageKey('playback-test-list-$tab'),
                            itemCount: 40,
                            itemBuilder: (_, index) => SizedBox(
                              height: 60,
                              child: Text('$tab/$index'),
                            ),
                          ),
                        ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('remounted info uses the selected tab over a saved page offset', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('评论'));
    await tester.pumpAndSettle();
    expect(find.text('1/0').hitTestable(), findsOneWidget);
    update(() => visible = false);
    await tester.pumpAndSettle();
    update(() {
      visible = true;
      value = 0;
    });
    await tester.pumpAndSettle();
    expect(value, 0);
    expect(find.text('0/0').hitTestable(), findsOneWidget);
    expect(find.text('正在加载…').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pager isolation preserves descendant list scroll storage', (
    tester,
  ) async {
    await mount(tester);
    final list = find.byKey(const PageStorageKey('playback-test-list-0'));
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    position().jumpTo(240);
    await tester.pumpAndSettle();
    await tester.tap(find.text('评论'));
    await tester.pumpAndSettle();
    update(() => visible = false);
    await tester.pumpAndSettle();
    update(() {
      visible = true;
      value = 0;
    });
    await tester.pumpAndSettle();
    expect(position().pixels, 240);
    expect(find.text('0/4').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained pages keep separate workspace scroll namespaces', (
    tester,
  ) async {
    await mount(tester);
    final list = find.byKey(const PageStorageKey('playback-test-list-0'));
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    position().jumpTo(240);
    await tester.pumpAndSettle();
    update(() => slot = 1);
    await tester.pumpAndSettle();
    expect(position().pixels, 0);
    position().jumpTo(480);
    await tester.pumpAndSettle();
    update(() => slot = 0);
    await tester.pumpAndSettle();
    expect(position().pixels, 240);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short, cancelled and mouse drags keep playback info selection', (
    tester,
  ) async {
    await mount(tester);
    final short = await tester.startGesture(tester.getCenter(pager));
    await short.moveBy(const Offset(-60, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await short.up();
    await tester.pumpAndSettle();
    expect(value, 0);
    final cancelled = await tester.startGesture(tester.getCenter(pager));
    await cancelled.moveBy(const Offset(-260, 0));
    await tester.pump();
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(value, 0);
    await tester.drag(
      pager,
      const Offset(-260, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(value, 0);
    expect(changes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hiding info during a drag cancels its pending selection', (
    tester,
  ) async {
    await mount(tester);
    final drag = await tester.startGesture(tester.getCenter(pager));
    await drag.moveBy(const Offset(-260, 0));
    await tester.pump();
    update(() => active = false);
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(value, 0);
    expect(changes, 0);
    update(() => active = true);
    await tester.pumpAndSettle();
    await tester.drag(pager, const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(value, 1);
    expect(changes, 1);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets('playback tab taps honor reduced motion: $reduced', (
      tester,
    ) async {
      await mount(tester, disableAnimations: reduced);
      await tester.tap(find.text('评论'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final strip = tester.widget<PagingTabStrip<int>>(
        find.byType(PagingTabStrip<int>),
      );
      expect(value, 1);
      expect(strip.progress?.value, reduced ? 1 : inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(find.text('1/0').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
