import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/video/application/video_extras_controller.dart';
import 'package:bilisail/features/video/domain/video_extras_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'related filtering changes and opt-out reuse a single remote read',
    () async {
      final repository = _Extras();
      final container = ProviderContainer(
        overrides: [
          videoExtrasRepositoryProvider.overrideWithValue(repository),
          settingsRepositoryProvider.overrideWithValue(_Settings()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      const id = VideoId('BV1234567890');
      final subscription = container.listen(
        relatedVideosProvider(id),
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(
        (await container.read(filteredRelatedVideosProvider(id).future)).length,
        2,
      );
      final settings = container.read(settingsControllerProvider.notifier);
      await settings.setRecommendations(
        RecommendationSettings(titleKeywords: ['blocked']),
      );
      expect(
        (await container.read(filteredRelatedVideosProvider(id).future))
            .single
            .title,
        'keep',
      );
      await settings.setRecommendations(
        RecommendationSettings(
          titleKeywords: ['blocked'],
          filterRelated: false,
        ),
      );
      expect(
        (await container.read(filteredRelatedVideosProvider(id).future)).length,
        2,
      );
      expect(repository.reads, 1);
      container.invalidate(relatedVideosProvider(id));
      expect(
        (await container.read(filteredRelatedVideosProvider(id).future)).length,
        2,
      );
      expect(repository.reads, 2);
    },
  );
}

final class _Settings implements SettingsRepository {
  AppSettings value = const AppSettings.defaults();
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async => value = settings;
}

final class _Extras implements VideoExtrasRepository {
  int reads = 0;
  @override
  Future<List<VideoSummary>> loadRelated(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async {
    reads++;
    return [
      for (final title in ['blocked', 'keep'])
        VideoSummary(
          id: VideoId(title),
          title: title,
          coverUrl: '',
          author: '',
          duration: const Duration(minutes: 1),
        ),
    ];
  }

  @override
  Future<List<String>> loadTags(
    VideoId id, {
    required RequestCancellation cancellation,
  }) => throw UnimplementedError();
  @override
  Future<VideoCommentsPage> loadComments(
    VideoId id, {
    required int page,
    required RequestCancellation cancellation,
  }) => throw UnimplementedError();
}
