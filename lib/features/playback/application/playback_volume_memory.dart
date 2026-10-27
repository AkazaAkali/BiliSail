/// Shared by formal playback pages, with optional persistence across runs.
final class PlaybackVolumeMemory {
  PlaybackVolumeMemory({this._savedVolume, this.saveVolume, this.onSaveError});

  final Future<void> Function(double)? saveVolume;
  final void Function(Object, StackTrace)? onSaveError;
  double? _volume;
  double? _savedVolume;
  double? _pendingSave;
  Future<void>? _saving;
  (Object, StackTrace)? _saveFailure;
  bool _enabled = false;
  int _revision = 0;

  double volumeFor(double defaultVolume) =>
      _volume ?? (_enabled ? _savedVolume : null) ?? defaultVolume;

  void configure({required bool enabled, required double defaultVolume}) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (enabled) _persist(volumeFor(defaultVolume));
  }

  int beginChange() => ++_revision;

  /// A slower native command must not replace a newer choice in another tab.
  void remember(double volume, {required int revision}) {
    if (revision != _revision || !volume.isFinite) return;
    final next = volume.clamp(0, 100).toDouble();
    _volume = next;
    if (_enabled) _persist(next);
  }

  void _persist(double volume) {
    _savedVolume = volume;
    if (saveVolume == null) return;
    _pendingSave = volume;
    _savePending();
  }

  void _savePending() {
    final save = saveVolume;
    if (save == null) return;
    // At most one write and one latest pending value, even during slider drags.
    _saving ??=
        Future<void>.microtask(() async {
          while (true) {
            final next = _pendingSave;
            if (next == null) break;
            _pendingSave = null;
            try {
              await save(next);
              _saveFailure = null;
            } catch (error, stack) {
              _saveFailure = (error, stack);
              onSaveError?.call(error, stack);
            }
          }
        }).whenComplete(() {
          _saving = null;
          if (_pendingSave != null) _savePending();
        });
  }

  Future<void> flush() async {
    while (true) {
      final saving = _saving;
      if (saving == null) break;
      await saving;
    }
    if (_saveFailure case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
  }
}
