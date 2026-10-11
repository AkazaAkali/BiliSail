import 'dart:convert';
import 'dart:io';

import 'package:bili_api/bili_api.dart';

/// Guest-only read probe. Never logs media URLs, headers or credentials.
Future<void> main() async {
  final api = BiliApiClient();
  void report(String kind, String id, ApiPlayInfo info) {
    final v = info.loudness;
    stdout.writeln(
      jsonEncode({
        'kind': kind,
        'id': id,
        'hasLoudness': v != null,
        if (v != null) ...{
          'measuredI': v.measuredI,
          'normalTargetI': v.normalTargetI,
          'highDynamicTargetI': v.highDynamicTargetI,
          'undersizedTargetI': v.undersizedTargetI,
        },
        'videoTracks': info.dashVideo.length,
        'audioTracks': info.dashAudio.length,
      }),
    );
  }

  try {
    report(
      'UGC',
      'BV11hpL62Ezv',
      await api.getPlayInfo('BV11hpL62Ezv', '42639298286'),
    );
    final pgc = PgcClient(api);
    final season = await pgc.getSeason(seasonId: '28747');
    final episode = season.episodes.where((e) => e.playable).firstOrNull;
    if (episode == null) {
      throw const ApiFailure(ApiFailureCategory.unavailable, 'pgc_season');
    }
    report('PGC', episode.episodeId, await pgc.getPlayInfo(episode.episodeId));
  } on ApiFailure catch (error) {
    stdout.writeln(
      jsonEncode({
        'endpoint': error.endpointId,
        'category': error.category.name,
        'businessCode': error.businessCode,
      }),
    );
    exitCode = 1;
  } finally {
    api.close();
  }
}
