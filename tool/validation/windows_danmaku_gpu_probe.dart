import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';

/// Local video plus synthetic danmaku. The candidate renderer is probe-only.
/// BILI_GPU_RENDERER=production/limited; BILI_GPU_MODE=scroll/fixed;
/// BILI_GPU_ARRIVALS=2/20; BILI_GPU_OPACITY=0.8/1.0.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setSize(const Size(1100, 700));
  final env = Platform.environment;
  final media = env['BILI_GPU_MEDIA'];
  final label = env['BILI_GPU_LABEL'];
  if (media == null || label == null) {
    throw StateError('BILI_GPU_MEDIA and BILI_GPU_LABEL are required');
  }
  final seconds = int.parse(env['BILI_GPU_SECONDS'] ?? '30');
  final renderer = env['BILI_GPU_RENDERER'] ?? 'production';
  final mode = env['BILI_GPU_MODE'] ?? 'scroll';
  final arrivals = int.parse(env['BILI_GPU_ARRIVALS'] ?? '20');
  final opacity = double.parse(env['BILI_GPU_OPACITY'] ?? '0.8');
  if (!['production', 'limited'].contains(renderer) ||
      !['scroll', 'fixed'].contains(mode) ||
      arrivals < 1 ||
      arrivals > 20 ||
      opacity < 0 ||
      opacity > 1) {
    throw StateError('Invalid probe scenario');
  }
  final file = File('build/validation/windows-gpu-playback-$label.jsonl');
  await file.parent.create(recursive: true);
  if (await file.exists()) throw StateError('Label already has playback data');
  final clock = Stopwatch()..start();
  final engine = MediaKitEngine();
  final danmaku = DanmakuController(monotonicNow: () => clock.elapsed)
    ..configure(area: 0.75, speed: 1);
  final enabled = ValueNotifier(false);
  final timings = <FrameTiming>[];
  void recordTimings(List<FrameTiming> frames) => timings.addAll(frames);
  SchedulerBinding.instance.addTimingsCallback(recordTimings);
  final subscription = engine.snapshots.listen((snapshot) {
    danmaku.sync(
      confirmedPosition: snapshot.position,
      playing: snapshot.phase == PlaybackPhase.playing,
      buffering: snapshot.isBuffering,
      seeking: snapshot.isSeeking,
      rate: snapshot.rate,
    );
  });
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 960,
            height: 540,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoSurface(engine: engine),
                ValueListenableBuilder<bool>(
                  valueListenable: enabled,
                  builder: (context, active, _) => active
                      ? Opacity(
                          opacity: opacity,
                          child: renderer == 'production'
                              ? DanmakuOverlay(
                                  controller: danmaku,
                                  bottomInset: 48,
                                )
                              : _LimitedOverlay(controller: danmaku),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Timer? windowRefresh;
  void refreshWindow() {
    final at = engine.currentSnapshot.position.inMicroseconds;
    final from = ((at - 9000000) * arrivals ~/ 1000000).clamp(0, 1000000);
    final until = (at + 10000000) * arrivals ~/ 1000000;
    danmaku.replaceEvents([
      for (var index = from; index < until; index++)
        DanmakuEvent(
          id: '$index',
          at: Duration(microseconds: index * 1000000 ~/ arrivals),
          text: '${_texts[index % _texts.length]} $index',
          fontSize: 25,
          mode: mode == 'scroll'
              ? DanmakuMode.scroll
              : (index.isEven ? DanmakuMode.top : DanmakuMode.bottom),
        ),
    ], sorted: true);
  }

  Future<void> stage(String name, int count) async {
    debugPrint('GPU_STAGE $name ${DateTime.now().toUtc().toIso8601String()}');
    timings.clear();
    for (var index = 0; index < count; index++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final snapshot = engine.currentSnapshot;
      final diagnostic = engine.inspectDiagnostics();
      final native = await engine.inspectNativePlaybackTiming();
      final raster = danmaku.rasterStatistics;
      await file.writeAsString(
        '${jsonEncode({'stage': name, 'pid': pid, 'timeUtc': DateTime.now().toUtc().toIso8601String(), 'renderer': renderer, 'mode': mode, 'arrivalsPerSecond': arrivals, 'opacity': opacity, 'positionMs': snapshot.position.inMilliseconds, 'phase': snapshot.phase.name, 'buffering': snapshot.isBuffering, 'decodedWidth': diagnostic.videoWidth, 'decodedHeight': diagnostic.videoHeight, 'outputWidth': diagnostic.outputWidth, 'outputHeight': diagnostic.outputHeight, 'hwdec': await engine.inspectHardwareDecoder(), 'avsyncSeconds': native.avsyncSeconds, 'frameDrops': native.frameDrops, 'decoderDrops': native.decoderDrops, 'dartFrames': timings.length, 'uiUs': timings.map((f) => f.buildDuration.inMicroseconds).toList(), 'rasterUs': timings.map((f) => f.rasterDuration.inMicroseconds).toList(), 'visible': danmaku.visibleCount, 'dropped': danmaku.dropped, 'layoutBuilds': danmaku.textLayoutBuildCount, 'rasterBytes': danmaku.textRasterBytes, 'imagePaints': raster.imagePaints, 'cacheHits': raster.cacheHits, 'rasterBuilds': raster.rasterBuilds, 'directPaints': raster.directPaints})}\n',
        mode: FileMode.append,
      );
      timings.clear();
    }
  }

  try {
    await engine.open(
      ProgressiveSource(
        MediaTrack(
          uri: File(media).absolute.uri,
          requestPolicy: MediaRequestPolicy(),
        ),
      ),
      const OpenOptions(play: true, volume: 0),
    );
    await stage('video-warmup', 3);
    await stage('video', 10);
    await engine.seek(Duration.zero);
    refreshWindow();
    windowRefresh = Timer.periodic(
      const Duration(seconds: 1),
      (_) => refreshWindow(),
    );
    enabled.value = true;
    await stage('danmaku-warmup', 8);
    await stage('danmaku', seconds);
    windowRefresh.cancel();
    await engine.pause();
    enabled.value = false;
    await stage('paused', 3);
  } finally {
    windowRefresh?.cancel();
    await subscription.cancel();
    SchedulerBinding.instance.removeTimingsCallback(recordTimings);
    enabled.dispose();
    danmaku.dispose();
    await engine.dispose();
  }
  exit(0);
}

const _texts = [
  '这个画面很好看',
  '弹幕与视频同播测试',
  '前方高能注意',
  '欢迎来到哔帆',
  '这段值得再看一次',
  '连续移动文字样本',
];

/// Test 60Hz presentation without changing media/animation clocks or images.
/// Fixed text only invalidates paint when content or positions actually change.
final class _LimitedOverlay extends StatefulWidget {
  const _LimitedOverlay({required this.controller});
  final DanmakuController controller;
  @override
  State<_LimitedOverlay> createState() => _LimitedOverlayState();
}

final class _LimitedOverlayState extends State<_LimitedOverlay> {
  final _repaint = ValueNotifier(0);
  List<DanmakuPlacement> _placements = const [];
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(microseconds: 16667), (_) {
      final next = widget.controller.frame();
      final unchanged =
          next.length == _placements.length &&
          Iterable<int>.generate(next.length).every(
            (i) =>
                identical(next[i].event, _placements[i].event) &&
                next[i].x == _placements[i].x &&
                next[i].y == _placements[i].y,
          );
      _placements = next;
      if (!unchanged) _repaint.value++;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.controller.setViewport(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            bottomInset: 48,
          );
        }
      });
      return RepaintBoundary(
        child: CustomPaint(
          painter: _ProbePainter(
            widget.controller,
            () => _placements,
            _repaint,
            MediaQuery.devicePixelRatioOf(context),
          ),
          size: Size.infinite,
        ),
      );
    },
  );

  @override
  void dispose() {
    _timer?.cancel();
    _repaint.dispose();
    super.dispose();
  }
}

final class _ProbePainter extends CustomPainter {
  _ProbePainter(this.controller, this.placements, Listenable repaint, this.dpr)
    : super(repaint: repaint);
  final DanmakuController controller;
  final List<DanmakuPlacement> Function() placements;
  final double dpr;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final item in placements()) {
      controller.paintText(
        item.event,
        canvas,
        Offset(item.x, item.y),
        pixelRatio: dpr,
      );
    }
  }

  @override
  bool shouldRepaint(_ProbePainter oldDelegate) =>
      !identical(controller, oldDelegate.controller) || dpr != oldDelegate.dpr;
}
