import 'package:bili_player/bili_player.dart';
import 'package:flutter/widgets.dart';

/// Supplies test pixels without adding presentation methods to PlayerEngine.
final class FakeVideoOutput implements FlutterVideoOutput {
  FakeVideoOutput(this.build);
  final Widget Function() build;

  @override
  Widget buildVideoSurface() => build();

  @override
  void attach(Object owner) {}

  @override
  void updateViewport(
    Object owner, {
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) {}

  @override
  void detach(Object owner) {}
}
