/// Shared by playback pages for one application run; never persisted.
final class PlaybackVolumeMemory {
  double? _volume;
  int _revision = 0;

  double volumeFor(double defaultVolume) => _volume ?? defaultVolume;

  int beginChange() => ++_revision;

  /// A slower native command must not replace a newer choice in another tab.
  void remember(double volume, {required int revision}) {
    if (revision == _revision) _volume = volume;
  }
}
