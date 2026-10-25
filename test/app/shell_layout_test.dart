import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/workspace_navigation.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'narrow navigation has four destinations and desktop keeps live separate',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(
        MaterialApp(
          theme: BiliTheme.light(),
          home: const BiliAppShell(
            navigationMode: WorkspaceNavigationMode.dualTabs,
            location: '/',
            child: SizedBox.expand(key: ValueKey('retained-content')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final content = tester.element(
        find.byKey(const ValueKey('retained-content')),
      );
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        bar.destinations.whereType<NavigationDestination>().map(
          (item) => item.label,
        ),
        ['首页', '动态', '我的', '设置'],
      );
      expect(find.byKey(const ValueKey('channel-live')), findsOneWidget);
      for (final width in [600.0, 960.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpAndSettle();
        expect(
          tester.element(find.byKey(const ValueKey('retained-content'))),
          same(content),
        );
        expect(find.byType(NavigationBar), findsNothing);
        expect(
          find.byKey(const ValueKey('workspace-nav-live')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('channel-live')), findsNothing);
        expect(find.byKey(const ValueKey('channel-bangumi')), findsOneWidget);
        expect(find.byKey(const ValueKey('channel-cinema')), findsOneWidget);
        expect(find.text('媒体库'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'desktop utilities stay at the bottom while main navigation scrolls',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: BiliTheme.light(),
          home: const BiliAppShell(
            navigationMode: WorkspaceNavigationMode.dualTabs,
            location: '/',
            child: SizedBox.expand(key: ValueKey('retained-content')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(
        find.byKey(const ValueKey('workspace-brand-logo')),
      );
      expect(
        (image.image as AssetImage).assetName,
        'assets/branding/app_icon.png',
      );
      final content = tester.element(
        find.byKey(const ValueKey('retained-content')),
      );
      for (final size in const [
        Size(1280, 844),
        Size(600, 844),
        Size(600, 320),
        Size(1280, 320),
        Size(720, 240),
        Size(1280, 240),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        final side = tester.getRect(
          find.byKey(const ValueKey('workspace-side-navigation')),
        );
        final utilities = [
          for (final name in ['messages', 'downloads', 'settings'])
            find.byKey(ValueKey('workspace-nav-$name')),
        ];
        for (final utility in utilities) {
          expect(
            utility.hitTestable(),
            findsOneWidget,
            reason: '$size $utility',
          );
        }
        final before = utilities.map(tester.getRect).toList();
        expect(side.bottom - before.last.bottom, closeTo(15, 0.1));
        await tester.drag(
          find.byKey(const ValueKey('workspace-primary-navigation')),
          const Offset(0, -350),
        );
        await tester.pumpAndSettle();
        expect(utilities.map(tester.getRect), before);
        expect(
          find.byKey(const ValueKey('workspace-nav-mine')).hitTestable(),
          findsOneWidget,
        );
        expect(
          tester.element(find.byKey(const ValueKey('retained-content'))),
          same(content),
        );
        expect(tester.takeException(), isNull, reason: '$size');
      }
    },
  );

  testWidgets(
    'mine keeps channels without common tools',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final location in [
        '/?channel=watchLater',
        '/?channel=favorites',
        '/me',
        '/history',
        '/downloads',
        '/messages',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: BiliAppShell(
              key: ValueKey(location),
              location: location,
              navigationMode: WorkspaceNavigationMode.dualTabs,
              accountBuilder: (_) => const Icon(Icons.account_circle),
              child: const SizedBox.expand(),
            ),
          ),
        );
        for (final width in [320.0, 390.0, 600.0, 1280.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('workspace-common-tools')),
            findsNothing,
            reason: '$location width=$width',
          );
          expect(find.byIcon(Icons.account_circle), findsNothing);
          expect(find.byKey(const ValueKey('workspace-search')), findsNothing);
          if (Uri.parse(location).queryParameters['channel']
              case final channel?) {
            expect(find.byKey(ValueKey('channel-$channel')), findsOneWidget);
          } else {
            expect(
              find.byKey(const ValueKey('home-channel-strip')),
              findsNothing,
            );
          }
          expect(
            find.byKey(const ValueKey('workspace-bottom-navigation')),
            width < 600 ? findsOneWidget : findsNothing,
          );
          final hasBack =
              location == '/history' ||
              (location == '/messages' &&
                  Theme.of(tester.element(find.byType(BiliAppShell)))
                          .platform ==
                      TargetPlatform.android);
          expect(
            find.byKey(const ValueKey('workspace-page-back-header')),
            hasBack ? findsOneWidget : findsNothing,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$location width=$width',
          );
        }
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'dynamic shows tools only on wide layouts and keeps a recognizable icon',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final channel in ['dynamic', 'videoDynamic']) {
        await tester.pumpWidget(
          MaterialApp(
            home: BiliAppShell(
              key: ValueKey(channel),
              location: '/?channel=$channel',
              navigationMode: WorkspaceNavigationMode.multipleTabs,
              accountBuilder: (_) => const Icon(Icons.account_circle),
              child: const SizedBox.expand(),
            ),
          ),
        );
        for (final width in [320.0, 390.0, 600.0, 1280.0]) {
          tester.view.physicalSize = Size(width, 844);
          await tester.pumpAndSettle();
          expect(
            find.byIcon(Icons.account_circle),
            width < 600 ? findsNothing : findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('workspace-search')),
            width < 600 ? findsNothing : findsOneWidget,
          );
          expect(find.byKey(const ValueKey('channel-dynamic')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('channel-videoDynamic')),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  const ['观看历史', '下载', '设置'].contains(widget.tooltip),
            ),
            findsNothing,
          );
          final tabIcon = tester.widget<Icon>(
            find.descendant(
              of: find.byKey(const ValueKey('workspace-tab-home')),
              matching: find.byType(Icon),
            ),
          );
          expect(tabIcon.icon, Icons.rss_feed_rounded);
          if (width >= 600) {
            final icon = tester.widget<Icon>(
              find.descendant(
                of: find.byKey(const ValueKey('workspace-nav-dynamic')),
                matching: find.byType(Icon),
              ),
            );
            expect(icon.icon, Icons.rss_feed_rounded);
          } else {
            final bar = tester.widget<NavigationBar>(
              find.byType(NavigationBar),
            );
            final destination = bar.destinations
                .whereType<NavigationDestination>()
                .singleWhere((item) => item.label == '动态');
            expect((destination.icon as Icon).icon, Icons.rss_feed_rounded);
            expect(
              (destination.selectedIcon as Icon).icon,
              Icons.rss_feed_rounded,
            );
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '$channel width=$width',
          );
        }
      }
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'compact dynamic tabs split the top safe area width with centered labels',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final channel in ['dynamic', 'videoDynamic']) {
        for (final (width, scale) in [
          (320.0, 1.0),
          (390.0, 1.0),
          (599.0, 1.0),
          (320.0, 2.0),
        ]) {
          tester.view.physicalSize = Size(width, 844);
          await tester.pumpWidget(
            MaterialApp(
              theme: BiliTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 24),
                  textScaler: TextScaler.linear(scale),
                ),
                child: child ?? const SizedBox.shrink(),
              ),
              home: BiliAppShell(
                key: ValueKey(channel),
                location: '/?channel=$channel',
                navigationMode: WorkspaceNavigationMode.dualTabs,
                accountBuilder: (_) => const Icon(Icons.account_circle),
                child: const SizedBox.expand(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('workspace-common-tools')),
            findsNothing,
          );
          expect(
            tester
                .getRect(find.byKey(const ValueKey('home-channel-strip')))
                .top,
            24,
          );
          for (final (index, name) in ['dynamic', 'videoDynamic'].indexed) {
            final tab = find.byKey(ValueKey('channel-$name'));
            final rect = tester.getRect(tab);
            expect(rect.width, closeTo(width / 2, .01));
            expect(rect.left, closeTo(index * width / 2, .01));
            final label = find.descendant(of: tab, matching: find.byType(Row));
            expect(tester.getCenter(label).dx, closeTo(rect.center.dx, .01));
            expect(
              find.descendant(of: label, matching: find.byType(Icon)),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: label,
                matching: find.text(index == 0 ? '动态' : '视频动态'),
              ),
              findsOneWidget,
            );
            expect(tab.hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'home and search keep account and search without shortcut tools',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final location in ['/', '/search?q=cat']) {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: BiliAppShell(
                key: ValueKey(location),
                location: location,
                navigationMode: WorkspaceNavigationMode.dualTabs,
                accountBuilder: (_) => const Icon(Icons.account_circle),
                pageBuilder: (_, tab) => tab.location.path == '/search'
                    ? Builder(
                        builder: (context) => WorkspacePageHeader.wrap(
                          context,
                          const SizedBox.expand(),
                        ),
                      )
                    : const SizedBox.expand(),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        );
        for (final width in [320.0, 390.0, 600.0, 1280.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.account_circle), findsOneWidget);
          expect(
            find.byKey(const ValueKey('workspace-search')),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  const ['观看历史', '下载', '设置'].contains(widget.tooltip),
            ),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('search-category-strip')),
            location == '/' ? findsNothing : findsOneWidget,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$location width=$width',
          );
        }
      }
    },
  );

  testWidgets('desktop live shows business sections with account and search', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: BiliTheme.light(),
        home: BiliAppShell(
          location: '/?channel=live&section=我的关注',
          navigationMode: WorkspaceNavigationMode.multipleTabs,
          accountBuilder: (_) => const Icon(Icons.account_circle),
          child: const SizedBox.expand(key: ValueKey('live-content')),
        ),
      ),
    );
    Element? content;
    for (final width in [600.0, 960.0, 1440.0, 390.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpAndSettle();
      content ??= tester.element(find.byKey(const ValueKey('live-content')));
      expect(
        tester.element(find.byKey(const ValueKey('live-content'))),
        same(content),
      );
      expect(find.byIcon(Icons.account_circle), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-search')), findsOneWidget);
      expect(find.text('全部分区'), findsNothing);
      expect(find.byKey(const ValueKey('channel-ranking')), findsNothing);
      expect(find.byKey(const ValueKey('workspace-back')), findsNothing);
      if (width >= 600) {
        expect(find.byKey(const ValueKey('home-channel-strip')), findsNothing);
        expect(find.byKey(const ValueKey('channel-live')), findsNothing);
        for (final section in ['推荐直播', '我的关注', '观看记录']) {
          expect(
            find.byKey(ValueKey('workspace-live-section-$section')),
            findsOneWidget,
          );
        }
      } else {
        expect(find.byKey(const ValueKey('channel-live')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('workspace-live-section-strip')),
          findsNothing,
        );
        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(
          bar.destinations.whereType<NavigationDestination>().map(
            (item) => item.label,
          ),
          ['首页', '动态', '我的', '设置'],
        );
      }
      expect(tester.takeException(), isNull, reason: '$width');
    }
  });

  testWidgets('keyboard height changes retain active and hidden page widgets', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BiliAppShell(
          location: '/video/BV1abc123456',
          navigationMode: WorkspaceNavigationMode.dualTabs,
          pageBuilder: (_, tab) {
            builds++;
            return SizedBox.expand(key: ValueKey('page-${tab.location.path}'));
          },
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final active = find.byKey(const ValueKey('page-/video/BV1abc123456'));
    final element = tester.element(active);
    final before = tester.getSize(active);
    builds = 0;
    for (final inset in [100.0, 200.0, 320.0, 160.0, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump();
      expect(builds, 0);
      expect(tester.element(active), same(element));
      expect(tester.getSize(active).height, before.height - inset);
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final dark in [false, true]) {
    testWidgets('home labels follow font changes in dark=$dark', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [375.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 800);
        Element? firstTab;
        for (final (font, family) in [
          (AppFontPreference.harmonyOsSans, ''),
          (AppFontPreference.installed, 'Microsoft YaHei'),
          (AppFontPreference.installed, 'Segoe UI'),
          (AppFontPreference.system, ''),
          (AppFontPreference.harmonyOsSans, ''),
        ]) {
          final theme = (dark ? BiliTheme.dark : BiliTheme.light)(
            font: font,
            systemFontFamily: family,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: const BiliAppShell(location: '/', child: SizedBox.expand()),
            ),
          );
          await tester.pumpAndSettle();
          for (final channel in channelsForSection(
            WorkspaceSection.home,
            compact: width < 600,
          )) {
            final tab = find.byKey(ValueKey('channel-${channel.name}'));
            final label = find.descendant(
              of: find.descendant(of: tab, matching: find.text(channel.label)),
              matching: find.byType(RichText),
            );
            final style = tester
                .renderObject<RenderParagraph>(label)
                .text
                .style;
            expect(
              style?.fontFamily,
              theme.textTheme.labelLarge?.fontFamily,
              reason: '${channel.name} font=$font family=$family width=$width',
            );
            expect(style?.fontSize, 14);
            expect(style?.fontWeight, FontWeight.w500);
          }
          final element = tester.element(
            find.byKey(const ValueKey('channel-recommended')),
          );
          firstTab ??= element;
          expect(element, same(firstTab));
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
  for (final mode in WorkspaceNavigationMode.values) {
    testWidgets(
      'messages hide home navigation and common tools across resizing in $mode',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: BiliAppShell(
              location: '/messages',
              navigationMode: mode,
              accountBuilder: (_) => const Icon(Icons.account_circle),
              child: const SizedBox.expand(key: ValueKey('message-content')),
            ),
          ),
        );
        for (final width in [320.0, 759.0, 760.0, 1200.0, 400.0]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('home-channel-strip')),
            findsNothing,
          );
          expect(find.byIcon(Icons.account_circle), findsNothing);
          expect(find.byKey(const ValueKey('workspace-search')), findsNothing);
          expect(find.byTooltip('观看历史'), findsNothing);
          expect(
            find.byKey(const ValueKey('workspace-bottom-navigation')),
            width < 600 ? findsOneWidget : findsNothing,
          );
          final tabs = find.byKey(const ValueKey('workspace-tab-strip'));
          final headerBottom = tabs.evaluate().isNotEmpty
              ? tester.getBottomLeft(tabs).dy
              : 0;
          final pageBack = find.byKey(
            const ValueKey('workspace-page-back-header'),
          );
          final pageBackHeight = pageBack.evaluate().isEmpty
              ? 0
              : tester.getSize(pageBack).height;
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('message-content'))).dy,
            headerBottom + pageBackHeight + (width >= 600 ? 12 : 0),
          );
          expect(tester.takeException(), isNull, reason: 'window width $width');
        }
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.windows,
      }),
    );
  }
  testWidgets('shell fits narrow and wide windows at double text scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final width in [400.0, 720.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const BiliAppShell(location: '/', child: SizedBox.expand()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'window width $width');
      expect(find.byKey(const ValueKey('channel-recommended')), findsOneWidget);
    }
  });
}
