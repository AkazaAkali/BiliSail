import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../../domain/recommendation_settings.dart';
import '../../../shared/application/recommendation_filter_provider.dart';
import '../domain/video_extras_repository.dart';

final videoExtrasRepositoryProvider = Provider<VideoExtrasRepository>(
  (ref) =>
      throw UnimplementedError('VideoExtrasRepository must be provided by app'),
);
final videoTagsProvider = FutureProvider.autoDispose
    .family<List<String>, VideoId>(
      (ref, id) {
        final cancellation = RequestCancellation();
        ref.onDispose(cancellation.cancel);
        return ref
            .read(videoExtrasRepositoryProvider)
            .loadTags(id, cancellation: cancellation);
      },
      // The transport already bounds read retries; UI retries are explicit.
      retry: (_, _) => null,
    );
final relatedVideosProvider = FutureProvider.autoDispose
    .family<List<VideoSummary>, VideoId>((ref, id) {
      final cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return ref
          .read(videoExtrasRepositoryProvider)
          .loadRelated(id, cancellation: cancellation);
    }, retry: (_, _) => null);
final filteredRelatedVideosProvider = FutureProvider.autoDispose
    .family<List<VideoSummary>, VideoId>((ref, id) async {
      final filter = ref.watch(recommendationFilterProvider);
      final items = await ref.watch(relatedVideosProvider(id).future);
      if (!filter.enabledFor(RecommendationSurface.related)) return items;
      return List.unmodifiable(
        items.where(
          (item) => filter.allows(item, RecommendationSurface.related),
        ),
      );
    }, retry: (_, _) => null);
final videoCommentsProvider = FutureProvider.autoDispose
    .family<VideoCommentsPage, ({VideoId id, int page})>((ref, request) {
      final cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return ref
          .read(videoExtrasRepositoryProvider)
          .loadComments(
            request.id,
            page: request.page,
            cancellation: cancellation,
          );
    });
