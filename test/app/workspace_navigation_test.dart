import 'package:bilisail/app/workspace_navigation.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primary channel destinations jump while inner tabs animate', () {
    for (final compact in [false, true]) {
      for (final from in [HomeChannel.recommended, HomeChannel.popular]) {
        for (final to in [HomeChannel.dynamic, HomeChannel.videoDynamic]) {
          expect(
            shouldAnimateChannelSelection(from, to, compact: compact),
            isFalse,
          );
          expect(
            shouldAnimateChannelSelection(to, from, compact: compact),
            isFalse,
          );
        }
      }
      expect(
        shouldAnimateChannelSelection(
          HomeChannel.recommended,
          HomeChannel.popular,
          compact: compact,
        ),
        isTrue,
      );
      expect(
        shouldAnimateChannelSelection(
          HomeChannel.dynamic,
          HomeChannel.videoDynamic,
          compact: compact,
        ),
        isTrue,
      );
      expect(
        shouldAnimateChannelSelection(
          HomeChannel.live,
          HomeChannel.bangumi,
          compact: compact,
        ),
        compact,
      );
    }
  });
  test('utility roots have distinct navigation identities', () {
    for (final (path, section) in [
      ('/messages', WorkspaceSection.messages),
      ('/downloads', WorkspaceSection.downloads),
      ('/settings', WorkspaceSection.settings),
    ]) {
      for (final compact in [false, true]) {
        expect(sectionForLocation(Uri.parse(path), compact: compact), section);
        expect(channelsForSection(section, compact: compact), isEmpty);
      }
    }
  });
  test(
    'every existing channel belongs to exactly one group at either width',
    () {
      for (final compact in [true, false]) {
        final sections = [
          WorkspaceSection.home,
          WorkspaceSection.dynamic,
          if (!compact) WorkspaceSection.live,
          WorkspaceSection.mine,
        ];
        final all = [
          for (final section in sections)
            ...channelsForSection(section, compact: compact),
        ];
        expect(all.toSet(), HomeChannel.primaryValues.toSet());
        expect(all.length, HomeChannel.primaryValues.length);
        for (final section in sections) {
          for (final channel in channelsForSection(section, compact: compact)) {
            expect(
              sectionForLocation(
                Uri.parse('/?channel=${channel.name}'),
                compact: compact,
              ),
              section,
            );
          }
        }
        expect(
          channelsForSection(WorkspaceSection.home, compact: compact),
          containsAll([
            HomeChannel.bangumi,
            HomeChannel.guochuang,
            HomeChannel.cinema,
          ]),
        );
      }
    },
  );
}
