import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/playback_repository.dart';

final playbackViewerRepositoryProvider = Provider<PlaybackViewerRepository?>(
  (ref) => null,
);

typedef PlaybackViewerRequest = ({VideoId video, String cid, int epoch});

final playbackViewersProvider = FutureProvider.autoDispose
    .family<String?, PlaybackViewerRequest>((ref, request) async {
      final repository = ref.watch(playbackViewerRepositoryProvider);
      final epoch = ref.read(sessionEpochProvider);
      if (repository == null || epoch() != request.epoch) return null;
      final cancellation = RequestCancellation();
      Timer? refresh;
      ref.onDispose(() {
        cancellation.cancel();
        refresh?.cancel();
      });
      try {
        final viewers = await repository.onlineViewers(
          request.video,
          request.cid,
          cancellation: cancellation,
        );
        return cancellation.isCancelled || epoch() != request.epoch
            ? null
            : viewers;
      } finally {
        // Start the interval after completion so slow reads cannot overlap.
        if (!cancellation.isCancelled && epoch() == request.epoch) {
          refresh = Timer(const Duration(seconds: 30), ref.invalidateSelf);
        }
      }
    }, retry: (_, _) => null);
