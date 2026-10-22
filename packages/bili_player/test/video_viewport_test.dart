import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _ViewportEngine
    implements PlayerEngine, VideoOutputSource, FlutterVideoOutput {
  @override
  VideoOutput get videoOutput => this;

  Object? owner;
  final updates = <({double width, double height, double dpr})>[];
  int attaches = 0;
  int detaches = 0;

  @override
  Widget buildVideoSurface() => const ColoredBox(color: Color(0xFF000000));

  @override
  void attach(Object value) {
    owner = value;
    attaches++;
  }

  @override
  void updateViewport(
    Object value, {
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) {
    if (!identical(value, owner)) return;
    updates.add((
      width: logicalWidth,
      height: logicalHeight,
      dpr: devicePixelRatio,
    ));
  }

  @override
  void detach(Object value) {
    if (!identical(value, owner)) return;
    owner = null;
    detaches++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('surface reports physical-pixel layout and transfers ownership', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(2560, 1440);
    addTearDown(tester.view.resetPhysicalSize);
    final engine = _ViewportEngine();
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 320,
          height: 180,
          child: VideoSurface(engine: engine),
        ),
      ),
    );
    expect(engine.attaches, 1);
    expect(engine.updates.single, (width: 320.0, height: 180.0, dpr: 2.0));

    // A fullscreen route replaces the inline surface while retaining the
    // player; only the new owner's layout can update its output.
    await tester.pumpWidget(const SizedBox());
    expect(engine.detaches, 1);
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 960,
          height: 540,
          child: VideoSurface(engine: engine),
        ),
      ),
    );
    expect(engine.attaches, 2);
    expect(engine.updates.last, (width: 960.0, height: 540.0, dpr: 2.0));
    expect(engine.updates, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    expect(engine.detaches, 2);
  });

  testWidgets('surface reserves pixels for painting scale without relayout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    final engine = _ViewportEngine();
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 320,
          height: 180,
          child: VideoSurface(engine: engine, paintScale: 1.05),
        ),
      ),
    );
    expect(tester.getSize(find.byType(VideoSurface)), const Size(320, 180));
    expect(engine.updates.single, (width: 336.0, height: 189.0, dpr: 2.0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Windows viewport shrinks after 300 ms but grows immediately', (
    tester,
  ) async {
    if (!Platform.isWindows) return;
    final engine = MediaKitEngine();
    final inline = Object();
    engine.videoOutput.attach(inline);
    engine.videoOutput.updateViewport(
      inline,
      logicalWidth: 640,
      logicalHeight: 360,
      devicePixelRatio: 2,
    );
    expect(engine.debugRequestedVideoViewport, (width: 1280, height: 768));
    engine.videoOutput.updateViewport(
      inline,
      logicalWidth: 320,
      logicalHeight: 180,
      devicePixelRatio: 2,
    );
    expect(engine.debugRequestedVideoViewport, (width: 1280, height: 768));
    await tester.pump(const Duration(milliseconds: 299));
    expect(engine.debugRequestedVideoViewport, (width: 1280, height: 768));
    await tester.pump(const Duration(milliseconds: 1));
    expect(engine.debugRequestedVideoViewport, (width: 640, height: 384));

    engine.videoOutput.updateViewport(
      inline,
      logicalWidth: 960,
      logicalHeight: 540,
      devicePixelRatio: 2,
    );
    expect(engine.debugRequestedVideoViewport, (width: 1920, height: 1088));
    final fullscreen = Object();
    engine.videoOutput.attach(fullscreen);
    expect(engine.debugRequestedVideoViewport, (width: null, height: null));
    engine.videoOutput.updateViewport(
      inline,
      logicalWidth: 100,
      logicalHeight: 100,
      devicePixelRatio: 1,
    );
    expect(engine.debugRequestedVideoViewport, (width: null, height: null));
    engine.videoOutput.updateViewport(
      fullscreen,
      logicalWidth: 800,
      logicalHeight: 450,
      devicePixelRatio: 1,
    );
    expect(engine.debugRequestedVideoViewport, (width: 832, height: 512));
    engine.videoOutput.updateViewport(
      fullscreen,
      logicalWidth: 320,
      logicalHeight: 180,
      devicePixelRatio: 1,
    );
    engine.videoOutput.detach(fullscreen);
    final replacement = Object();
    engine.videoOutput.attach(replacement);
    await tester.pump(const Duration(milliseconds: 301));
    expect(engine.debugRequestedVideoViewport, (width: null, height: null));
    final disposal = engine.dispose();
    await tester.pump();
    await disposal;
  });
}
