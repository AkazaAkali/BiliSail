import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/feed_video_grid.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/video_card_cover.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _video = VideoSummary(
  id: VideoId('BV1abc123456'),
  title: '完整卡片标题',
  author: '测试作者',
  coverUrl: '',
  duration: Duration(seconds: 30),
);

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'phone feed surface dark=$dark text=$scale preserves content and actions',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          tester.view.display.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          addTearDown(tester.view.display.reset);
          final theme = dark ? BiliTheme.dark() : BiliTheme.light();
          var opened = 0;
          Future<void> show({
            bool group = true,
            double displayWidth = 390,
          }) async {
            tester.view.display.size = Size(displayWidth, 844);
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: const Size(390, 844),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: 180,
                        child: VideoCard(
                          key: ValueKey(displayWidth),
                          video: _video,
                          onTap: () => opened++,
                          groupPhoneContent: group,
                          menu: const VideoCardMenu(
                            actions: [VideoCardMenuAction.notInterested],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          Material surface() => tester.widget<Material>(
            find
                .descendant(
                  of: find.byType(VideoCard),
                  matching: find.byType(Material),
                )
                .first,
          );
          await show(group: false);
          expect(surface().color, Colors.transparent);
          final menu = find.byKey(const ValueKey('video-card-title-menu'));
          final menuSize = tester.getSize(menu);
          await show();
          final mobile =
              defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS;
          expect(
            surface().color,
            mobile ? theme.colorScheme.surfaceContainerLow : Colors.transparent,
          );
          expect(tester.getSize(menu), menuSize);
          expect(
            find.descendant(
              of: find.byType(VideoCard),
              matching: find.byType(VideoCardCover),
            ),
            findsOneWidget,
          );
          expect(find.text(_video.author), findsOneWidget);
          await tester.tap(find.text(_video.title));
          await tester.pump();
          expect(opened, 1);
          if (mobile) {
            await tester.tap(menu);
            await tester.pumpAndSettle();
            expect(find.text('不感兴趣'), findsOneWidget);
            await tester.tapAt(const Offset(389, 843));
            await tester.pumpAndSettle();
            expect(opened, 1);
          }
          await show(displayWidth: 800);
          expect(surface().color, Colors.transparent);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.windows,
        }),
      );
    }
  }

  testWidgets('feed grid opts into grouped phone cards and retains gutters', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.display.devicePixelRatio = 1;
    tester.view.display.size = const Size(390, 844);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.display.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: BiliTheme.dark(),
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                FeedVideoGrid(
                  items: const [_video, _video, _video],
                  channel: HomeChannel.popular,
                  onReject: (_) {},
                  onUndo: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cards = find.byType(VideoCard);
    expect(tester.widget<VideoCard>(cards.first).groupPhoneContent, isTrue);
    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    final third = tester.getRect(cards.at(2));
    expect(second.left - first.right, 6);
    expect(third.top - first.bottom, 16);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
