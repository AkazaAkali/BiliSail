import 'dart:async';

import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_viewers_controller.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _first = (video: VideoId('BV1abc123456'), cid: '123', epoch: 0);

void main() {
  testWidgets('viewer refresh waits for completion and stops on disposal', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(_host(repository, _first));
    final container = _container(tester);
    final provider = playbackViewersProvider(_first);
    expect(repository.reads, hasLength(1));
    await tester.pump(const Duration(seconds: 40));
    expect(repository.reads, hasLength(1));
    repository.reads[0].result.complete('92');
    await tester.pump();
    expect(container.read(provider).asData?.value, '92');
    await tester.pump(const Duration(seconds: 29));
    expect(repository.reads, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repository.reads, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    expect(repository.reads[1].cancellation.isCancelled, isTrue);
    repository.reads[1].result.complete('100');
    await tester.pump(const Duration(seconds: 60));
    expect(repository.reads, hasLength(2));
  });

  testWidgets(
    'old part and account responses cannot populate the current count',
    (tester) async {
      var epoch = 0;
      int currentEpoch() => epoch;
      final repository = _Repository();
      await tester.pumpWidget(_host(repository, _first, epoch: currentEpoch));
      const next = (video: VideoId('BV1abc123456'), cid: '456', epoch: 1);
      epoch = 1;
      await tester.pumpWidget(_host(repository, next, epoch: currentEpoch));
      await tester.pump();
      expect(repository.reads[0].cancellation.isCancelled, isTrue);
      expect(repository.reads[1].cid, '456');
      repository.reads[1].result.complete('12');
      repository.reads[0].result.complete('999');
      await tester.pump();
      expect(
        _container(tester).read(playbackViewersProvider(next)).asData?.value,
        '12',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('account transition during a read discards its result', (
    tester,
  ) async {
    var epoch = 0;
    final repository = _Repository();
    await tester.pumpWidget(_host(repository, _first, epoch: () => epoch));
    final container = _container(tester);
    epoch++;
    repository.reads.single.result.complete('999');
    await tester.pump();
    expect(
      container.read(playbackViewersProvider(_first)).asData?.value,
      isNull,
    );
    await tester.pump(const Duration(seconds: 60));
    expect(repository.reads, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'read failures clear the count and recover on the next interval',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(_host(repository, _first));
      repository.reads.single.result.complete('92');
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      repository.reads.last.result.completeError(StateError('unavailable'));
      await tester.pump();
      expect(
        _container(tester).read(playbackViewersProvider(_first)).hasError,
        isTrue,
      );
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      repository.reads.last.result.complete('93');
      await tester.pump();
      expect(repository.reads, hasLength(3));
      expect(
        _container(tester).read(playbackViewersProvider(_first)).asData?.value,
        '93',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Widget _host(
  _Repository repository,
  PlaybackViewerRequest request, {
  int Function()? epoch,
}) => ProviderScope(
  overrides: [
    playbackViewerRepositoryProvider.overrideWithValue(repository),
    sessionEpochProvider.overrideWithValue(epoch ?? () => 0),
  ],
  child: Consumer(
    builder: (context, ref, _) {
      ref.watch(playbackViewersProvider(request));
      return const SizedBox(key: Key('viewer-probe'));
    },
  ),
);

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byKey(const Key('viewer-probe'))),
);

class _Repository implements PlaybackViewerRepository {
  final reads =
      <
        ({
          String cid,
          RequestCancellation cancellation,
          Completer<String?> result,
        })
      >[];
  @override
  Future<String?> onlineViewers(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) {
    final result = Completer<String?>();
    reads.add((cid: cid, cancellation: cancellation, result: result));
    return result.future;
  }
}
