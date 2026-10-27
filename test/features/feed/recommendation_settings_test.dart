import 'dart:async';

import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/filtered_feed_index.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

VideoSummary _video(String id, {String? title, int seconds = 60}) =>
    VideoSummary(
      id: VideoId(id),
      title: title ?? id,
      coverUrl: '',
      author: '',
      duration: Duration(seconds: seconds),
    );
PageResult<VideoSummary> _page(List<VideoSummary> items, {bool more = true}) =>
    PageResult(items: items, hasMore: more);

void main() {
  test('default index keeps one snapshot; enabled index handles same-ID removal and restoration', () {
    final defaults = RecommendationFilter(
      const RecommendationSettings.defaults(),
    );
    final index = FilteredFeedIndex(
      defaults,
      RecommendationSurface.recommended,
    );
    final first = _video('one');
    final snapshot = index.merge([first]);
    expect(identical(snapshot, index.rawItems), isTrue);
    index.configure(
      RecommendationFilter(RecommendationSettings(titleKeywords: ['blocked'])),
    );
    index.merge([_video('two')]);
    expect(identical(index.items.first, first), isTrue);
    index.merge([_video('one', title: 'blocked')]);
    expect(index.items.map((item) => item.id.value), ['two']);
    index.configure(defaults);
    expect(identical(index.items, index.rawItems), isTrue);
    expect(index.items.map((item) => item.id.value), ['one', 'two']);
    expect(snapshot.single.title, 'one');
    index.configure(
      RecommendationFilter(RecommendationSettings(titleKeywords: ['blocked'])),
    );
    index.merge([_video('three'), _video('three', title: 'blocked')]);
    expect(index.items.any((item) => item.id.value == 'three'), isFalse);
  });

  late ProviderContainer container;
  late _Feed feed;
  late FeedController controller;
  late SettingsController settings;
  setUp(() async {
    feed = _Feed();
    container = ProviderContainer(
      overrides: [
        feedRepositoryProvider.overrideWithValue(feed),
        settingsRepositoryProvider.overrideWithValue(_Settings()),
      ],
    );
    await container.read(settingsControllerProvider.future);
    settings = container.read(settingsControllerProvider.notifier);
    controller = container.read(feedControllerProvider.notifier);
  });
  tearDown(() => container.dispose());
  List<String> ids() => container
      .read(feedControllerProvider)
      .items
      .requireValue
      .map((item) => item.id.value)
      .toList();
  Future<void> configure(RecommendationSettings value) async {
    await settings.setRecommendations(value);
    await container.pump();
  }

  Future<void> refresh(List<VideoSummary> items) async {
    final future = controller.refresh();
    feed.calls.last.complete(_page(items));
    await future;
  }

  test('local rules update active and hidden channels and restore data without reads', () async {
    await refresh([_video('keep'), _video('blocked')]);
    final popular = controller.selectChannel(HomeChannel.popular);
    feed.calls.last.complete(_page([_video('popular'), _video('blocked')]));
    await popular;
    await configure(RecommendationSettings(titleKeywords: ['blocked']));
    expect(ids(), ['popular']);
    expect(
      controller
          .stateForChannel(HomeChannel.recommended)
          .items
          .requireValue
          .single
          .id
          .value,
      'keep',
    );
    await controller.selectRecommended();
    expect(ids(), ['keep']);
    await configure(const RecommendationSettings.defaults());
    expect(ids(), ['keep', 'blocked']);
    expect(feed.calls.length, 2);
  });

  test(
    'fully filtered pages retain the existing bounded empty-page budget',
    () async {
      await configure(RecommendationSettings(titleKeywords: ['blocked']));
      await refresh([_video('blocked')]);
      expect(ids(), isEmpty);
      final more = controller.loadMore();
      feed.calls.last.complete(_page([_video('blocked2')]));
      await more;
      expect(container.read(feedControllerProvider).pageError, isNotNull);
      expect(feed.calls.length, 2);
    },
  );

  test('refresh retains at most 200 old entries, fresh metadata wins, marker follows settings', () async {
    await configure(RecommendationSettings(keepPrevious: true));
    await refresh(List.generate(300, (index) => _video('old$index')));
    final future = controller.refresh();
    expect(container.read(feedControllerProvider).refreshing, isTrue);
    expect(ids().length, 300);
    feed.calls.last.complete(
      _page([_video('new'), _video('old0', title: 'updated')]),
    );
    await future;
    expect(ids().length, 201);
    expect(ids().take(3), ['new', 'old0', 'old1']);
    expect(
      container.read(feedControllerProvider).items.requireValue[1].title,
      'updated',
    );
    expect(container.read(feedControllerProvider).previousStartIndex, 2);
    await configure(
      RecommendationSettings(keepPrevious: true, showPreviousMarker: false),
    );
    expect(container.read(feedControllerProvider).previousStartIndex, isNull);
    await configure(RecommendationSettings(keepPrevious: true));
    expect(container.read(feedControllerProvider).previousStartIndex, 2);
    await refresh([_video('next')]);
    expect(ids().length, 201);
    expect(ids().first, 'next');
  });

  test('failed retained refresh preserves content; explicit retry restarts the first page', () async {
    await configure(RecommendationSettings(keepPrevious: true));
    await refresh([_video('old')]);
    final future = controller.refresh();
    feed.calls.last.completeError(StateError('offline'));
    await future;
    expect(ids(), ['old']);
    expect(container.read(feedControllerProvider).refreshing, isFalse);
    expect(container.read(feedControllerProvider).pageError, isNotNull);
    final retry = controller.loadMore();
    expect(feed.pages.last, 1);
    feed.calls.last.complete(_page([_video('fresh')]));
    await retry;
    expect(ids(), ['fresh', 'old']);
  });

  test('late refresh cannot replace a newly selected channel', () async {
    await configure(RecommendationSettings(keepPrevious: true));
    await refresh([_video('old')]);
    final pendingRefresh = controller.refresh();
    final late = feed.calls.last;
    final popular = controller.selectPopular();
    feed.calls.last.complete(_page([_video('popular')]));
    await popular;
    late.complete(_page([_video('late')]));
    await pendingRefresh;
    expect(ids(), ['popular']);
    final back = controller.selectRecommended();
    feed.calls.last.complete(_page([_video('back')]));
    await back;
    expect(ids(), ['back', 'old']);
    expect(container.read(feedControllerProvider).refreshing, isFalse);
  });

  test(
    'marker follows the first visible retained entry after rule changes',
    () async {
      await configure(RecommendationSettings(keepPrevious: true));
      await refresh([_video('old1'), _video('old2')]);
      await refresh([_video('new')]);
      await configure(
        RecommendationSettings(keepPrevious: true, titleKeywords: ['old1']),
      );
      expect(ids(), ['new', 'old2']);
      expect(container.read(feedControllerProvider).previousStartIndex, 1);
      await configure(
        RecommendationSettings(keepPrevious: true, titleKeywords: ['new']),
      );
      expect(ids(), ['old1', 'old2']);
      expect(container.read(feedControllerProvider).previousStartIndex, 0);
      await configure(RecommendationSettings(keepPrevious: true));
      expect(ids(), ['new', 'old1', 'old2']);
      expect(container.read(feedControllerProvider).previousStartIndex, 1);
      expect(feed.calls.length, 2);
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

final class _Feed implements FeedRepository {
  final calls = <Completer<PageResult<VideoSummary>>>[];
  final pages = <int>[];
  Future<PageResult<VideoSummary>> _read(int page) {
    pages.add(page);
    final call = Completer<PageResult<VideoSummary>>();
    calls.add(call);
    return call.future;
  }

  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) => _read(page);
  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) => _read(page);
}
