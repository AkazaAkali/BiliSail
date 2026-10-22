/// The presentation lifecycle of a video output, independent of playback.
///
/// The engine owns the output. Attaching or detaching a view must not play,
/// pause, seek, or dispose the engine. Implementations reject viewport updates
/// from an owner superseded by another inline, fullscreen, or preview surface.
abstract interface class VideoOutput {
  /// Attaches the current presentation owner.
  void attach(Object owner);

  /// Updates the owner's logical viewport and physical-pixel scale.
  void updateViewport(
    Object owner, {
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  });

  /// Detaches the owner without changing the user's playback intent.
  void detach(Object owner);
}

/// An optional, stable output associated with a playback runtime.
abstract interface class VideoOutputSource {
  VideoOutput get videoOutput;
}
