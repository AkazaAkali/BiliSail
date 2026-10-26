import 'package:flutter/services.dart';

import 'player_contract.dart';

/// Keep descriptors alive until mpv has disposed both video and external audio.
/// Raw fd:// sources are never accepted from a caller or persisted in an index.
final class AndroidMediaLeases {
  static const _channel = MethodChannel('dev.bilisail/download_storage');
  final List<String> _leases = [];

  Future<MediaTrack> open(MediaTrack track) async {
    if (track.uri.scheme != 'content') return track;
    final result = await _channel.invokeMapMethod<String, Object?>(
      'openMedia',
      {'uri': track.uri.toString()},
    );
    final lease = result?['lease'];
    final fd = result?['fd'];
    if (lease is! String || fd is! int || fd < 0) {
      throw StateError(
        'Android provider returned no readable media descriptor',
      );
    }
    _leases.add(lease);
    return MediaTrack(
      uri: Uri.parse('fd://$fd'),
      requestPolicy: MediaRequestPolicy(),
      codec: track.codec,
      bandwidth: track.bandwidth,
    );
  }

  Future<void> close() async {
    final pending = List<String>.of(_leases);
    _leases.clear();
    Object? failure;
    for (final lease in pending) {
      try {
        await _channel.invokeMethod<void>('closeMedia', {'lease': lease});
      } catch (e) {
        failure ??= e;
      }
    }
    if (failure != null) throw failure;
  }
}
