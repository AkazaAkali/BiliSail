import 'live_room.dart';

/// Context-free text/image pieces. Theme, scale and actions remain in the view.
final class LiveChatContentPart {
  const LiveChatContentPart(this.text, {this.image, this.sticker = false});
  final String text;
  final LiveChatImage? image;
  final bool sticker;
}

final class LiveChatContent {
  LiveChatContent(LiveChatMessage message)
    : text = message.text,
      emotes = Map.unmodifiable(message.emotes),
      sticker = message.sticker,
      parts = List.unmodifiable(_parse(message));

  final String text;
  final Map<String, LiveChatImage> emotes;
  final LiveChatImage? sticker;
  final List<LiveChatContentPart> parts;

  bool matches(LiveChatMessage message) =>
      text == message.text &&
      _sameImage(sticker, message.sticker) &&
      emotes.length == message.emotes.length &&
      emotes.entries.every(
        (entry) => _sameImage(entry.value, message.emotes[entry.key]),
      );

  static bool _sameImage(LiveChatImage? a, LiveChatImage? b) =>
      identical(a, b) ||
      (a != null &&
          b != null &&
          a.url == b.url &&
          a.width == b.width &&
          a.height == b.height);

  static Iterable<LiveChatContentPart> _parse(LiveChatMessage message) sync* {
    final sticker = message.sticker;
    if (sticker != null) {
      yield LiveChatContentPart(message.text, image: sticker, sticker: true);
      return;
    }
    // Keep longest-token precedence for matches at the same position.
    final tokens =
        message.emotes.keys.where((token) => token.isNotEmpty).toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    var cursor = 0;
    while (cursor < message.text.length) {
      String? token;
      var position = message.text.length;
      for (final candidate in tokens) {
        final at = message.text.indexOf(candidate, cursor);
        if (at >= 0 && at < position) {
          token = candidate;
          position = at;
        }
      }
      if (token == null) {
        yield LiveChatContentPart(message.text.substring(cursor));
        return;
      }
      if (position > cursor) {
        yield LiveChatContentPart(message.text.substring(cursor, position));
      }
      yield LiveChatContentPart(token, image: message.emotes[token]);
      cursor = position + token.length;
    }
  }
}

/// One screen owns this bounded cache and evicts entries with its chat window.
final class LiveChatContentCache {
  LiveChatContentCache({this.capacity = 500}) : assert(capacity > 0);
  final int capacity;
  final _entries = <String, LiveChatContent>{};

  int get length => _entries.length;

  LiveChatContent resolve(LiveChatMessage message) {
    final key = message.deduplicationKey;
    final previous = _entries.remove(key);
    final content = previous != null && previous.matches(message)
        ? previous
        : LiveChatContent(message);
    _entries[key] = content;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return content;
  }

  void retain(Set<String> keys) =>
      _entries.removeWhere((key, _) => !keys.contains(key));
}
