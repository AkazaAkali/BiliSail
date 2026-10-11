import 'pgc_repository.dart';

/// Advance within the selected 正片/SP section, using its original order.
PgcEpisode? adjacentPgcEpisode(
  PgcSeason season,
  PgcEpisode selected,
  int direction,
) {
  final next = season.adjacentEpisode(selected, direction);
  // Permission restrictions are a stopping point, not a reason to skip ahead.
  return next?.playable == true ? next : null;
}
