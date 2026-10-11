import 'package:bilisail/features/live/domain/live_chat_content.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final short = LiveChatImage(url: Uri.parse('https://i0.hdslb.com/short.png'));
  final long = LiveChatImage(url: Uri.parse('https://i0.hdslb.com/long.png'));

  test('text splitting preserves longest token, unknown text and sticker precedence', () {
    final content = LiveChatContent(
      LiveChatMessage(
        userName: 'name',
        text: '前[a]b后[a][未知]',
        emotes: {'': short, '[a]': short, '[a]b': long},
      ),
    );
    expect(content.parts.map((part) => part.text), [
      '前',
      '[a]b',
      '后',
      '[a]',
      '[未知]',
    ]);
    expect(content.parts[1].image, long);
    expect(content.parts[3].image, short);
    final sticker = LiveChatContent(
      LiveChatMessage(
        userName: 'name',
        text: '[a]',
        emotes: {'[a]': short},
        sticker: long,
      ),
    );
    expect(sticker.parts.single.sticker, isTrue);
    expect(sticker.parts.single.image, long);
  });

  test('500 retained messages reuse parsed content and evict entries with the window', () {
    final cache = LiveChatContentCache();
    final messages = List.generate(
      500,
      (index) => LiveChatMessage(
        id: '$index',
        userName: 'name',
        text: '$index [a]',
        emotes: {'[a]': short},
      ),
    );
    final parsed = messages.map(cache.resolve).toList();
    for (var batch = 0; batch < 20; batch++) {
      for (var index = 0; index < messages.length; index++) {
        expect(
          identical(cache.resolve(messages[index]), parsed[index]),
          isTrue,
        );
      }
    }
    expect(cache.length, 500);
    cache.resolve(
      const LiveChatMessage(id: 'new', userName: 'name', text: 'new'),
    );
    expect(cache.length, 500);
    expect(identical(cache.resolve(messages.first), parsed.first), isFalse);
    cache.retain({'0'});
    expect(cache.length, 1);
    final revised = cache.resolve(
      LiveChatMessage(
        id: '0',
        userName: 'name',
        text: '0 [a]',
        emotes: {'[a]': long},
      ),
    );
    expect(revised.parts.last.image, long);
    expect(identical(revised, parsed.first), isFalse);
    cache.retain({});
    expect(cache.length, 0);
  });
}
