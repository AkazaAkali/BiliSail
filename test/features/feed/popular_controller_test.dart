import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/popular_feed.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Repository repository;
  late ProviderContainer container;
  late FeedController controller;
  setUp(() {
    repository = _Repository();
    container = ProviderContainer(
      overrides: [feedRepositoryProvider.overrideWithValue(repository)],
    );
    controller = container.read(feedControllerProvider.notifier);
  });
  tearDown(() => container.dispose());
  FeedState state() => container.read(feedControllerProvider);

  test(
    'four popular sections retain separate results without reloading on return',
    () async {
      for (final section in PopularSection.values) {
        await controller.selectPopularSection(section);
        expect(state().popularSection, section);
        expect(
          state().items.requireValue.single.title,
          section == PopularSection.weekly ? 'week10' : section.name,
        );
      }
      for (final section in PopularSection.values) {
        await controller.selectPopularSection(section);
        expect(state().popularSection, section);
      }
      expect(repository.calls.where((call) => call == 'all1'), hasLength(1));
      expect(repository.calls.where((call) => call == 'week10'), hasLength(1));
      expect(
        repository.calls.where((call) => call == 'precious'),
        hasLength(1),
      );
      expect(
        repository.calls.where((call) => call == 'ranking0'),
        hasLength(1),
      );
    },
  );

  test('switching period cancels and rejects a late old period', () async {
    final pending = Completer<PageResult<VideoSummary>>();
    RequestCancellation? old;
    repository.weekRead = (number, cancellation) {
      if (number == 10) {
        old = cancellation;
        return pending.future;
      }
      return Future.value(_page('week$number'));
    };
    final first = controller.selectPopularSection(PopularSection.weekly);
    await Future<void>.delayed(Duration.zero);
    expect(state().weeklyIssue, 10);
    await controller.selectPopularWeek(9);
    expect(old?.isCancelled, isTrue);
    pending.complete(_page('late week10'));
    await first;
    expect(state().weeklyIssue, 9);
    expect(state().items.requireValue.single.title, 'week9');
  });

  test(
    'leaving weekly cancels its directory and cannot start a late week read',
    () async {
      final pending = Completer<List<PopularWeek>>();
      repository.directoryRead = (_) => pending.future;
      final first = controller.selectPopularSection(PopularSection.weekly);
      await controller.selectPopularSection(PopularSection.precious);
      pending.complete(repository.weeks);
      await first;
      expect(state().popularSection, PopularSection.precious);
      expect(state().items.requireValue.single.title, 'precious');
      expect(
        repository.calls.where((call) => call.startsWith('week')),
        isEmpty,
      );
    },
  );

  test(
    'period cache is bounded and a recent period returns without a request',
    () async {
      await controller.selectPopularSection(PopularSection.weekly);
      await controller.selectPopularWeek(9);
      await controller.selectPopularWeek(10);
      expect(repository.calls.where((call) => call == 'week10'), hasLength(1));
      for (final number in [8, 7, 6, 5, 4, 3, 2]) {
        await controller.selectPopularWeek(number);
      }
      await controller.selectPopularWeek(10);
      expect(repository.calls.where((call) => call == 'week10'), hasLength(2));
      expect(state().items.requireValue.single.title, 'week10');
    },
  );

  test(
    'refresh falls back to newest when the selected period was removed',
    () async {
      await controller.selectPopularSection(PopularSection.weekly);
      await controller.selectPopularWeek(9);
      repository.weeks = const [
        PopularWeek(number: 11, name: '新一期'),
        PopularWeek(number: 10, name: '上一期'),
      ];
      await controller.refresh();
      expect(state().weeklyIssue, 11);
      expect(state().items.requireValue.single.title, 'week11');
      expect(state().weeklyIssues.map((week) => week.number), [11, 10]);
      await controller.selectPopularWeek(9);
      expect(state().weeklyIssue, 11);
    },
  );

  test(
    'empty weekly directory is an empty selection and does not invent a period',
    () async {
      repository.weeks = const [];
      await controller.selectPopularSection(PopularSection.weekly);
      expect(state().weeklyIssue, isNull);
      expect(state().items.requireValue, isEmpty);
      expect(repository.calls, ['directory']);
    },
  );

  test(
    'weekly business denial remains an error until explicit retry',
    () async {
      repository.weekRead = (_, _) async =>
          throw const AppFailure(AppFailureKind.rateLimited, '服务暂时限制请求');
      await controller.selectPopularSection(PopularSection.weekly);
      expect(state().items.hasError, isTrue);
      expect(repository.calls, ['directory', 'week10']);
      repository.weekRead = null;
      await controller.refresh();
      expect(state().items.requireValue.single.title, 'week10');
      expect(repository.calls.where((call) => call == 'all1'), isEmpty);
      expect(repository.calls.where((call) => call == 'week10'), hasLength(2));
    },
  );

  test(
    'comprehensive popular continues after 500 according to server hasMore',
    () async {
      repository.allRead = (page) async => PageResult(
        items: [
          for (var index = (page - 1) * 300; index < page * 300; index++)
            _video('all$index'),
        ],
        hasMore: true,
      );
      await controller.selectPopularSection(PopularSection.all);
      await controller.loadMore();
      expect(state().items.requireValue, hasLength(600));
      expect(state().hasMore, isTrue);
      await controller.loadMore();
      expect(state().items.requireValue, hasLength(900));
      expect(repository.calls, ['all1', 'all2', 'all3']);
    },
  );

  test(
    'weekly, precious and rankings do not paginate complete lists',
    () async {
      for (final section in [
        PopularSection.weekly,
        PopularSection.precious,
        PopularSection.ranking,
      ]) {
        await controller.selectPopularSection(section);
        final reads = repository.calls.length;
        await controller.loadMore();
        expect(repository.calls.length, reads);
        expect(state().hasMore, isFalse);
      }
    },
  );

  test(
    'disposing page scope cancels period reads and clears retained state',
    () async {
      final pending = Completer<PageResult<VideoSummary>>();
      RequestCancellation? cancellation;
      repository.weekRead = (_, signal) {
        cancellation = signal;
        return pending.future;
      };
      final old = controller.selectPopularSection(PopularSection.weekly);
      await Future<void>.delayed(Duration.zero);
      container.invalidate(feedControllerProvider);
      expect(cancellation?.isCancelled, isTrue);
      pending.complete(_page('old account'));
      await old;
      expect(state().channel, HomeChannel.recommended);
      expect(state().weeklyIssue, isNull);
      expect(state().items.isLoading, isTrue);
    },
  );
}

VideoSummary _video(String title) => VideoSummary(
  id: VideoId(title),
  title: title,
  coverUrl: '',
  author: '测试作者',
  duration: Duration.zero,
);
PageResult<VideoSummary> _page(String title) =>
    PageResult(items: [_video(title)], hasMore: false);

class _Repository
    implements FeedRepository, PopularFeedRepository, RankingFeedRepository {
  List<PopularWeek> weeks = [
    for (var number = 10; number >= 1; number--)
      PopularWeek(number: number, name: '第$number期'),
  ];
  final calls = <String>[];
  Future<PageResult<VideoSummary>> Function(int, RequestCancellation)? weekRead;
  Future<List<PopularWeek>> Function(RequestCancellation)? directoryRead;
  Future<PageResult<VideoSummary>> Function(int)? allRead;

  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => const [];
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async => _page('recommended');
  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) {
    calls.add('all$page');
    return allRead?.call(page) ?? Future.value(_page('all'));
  }

  @override
  Future<List<PopularWeek>> loadPopularWeeks({
    required RequestCancellation cancellation,
  }) {
    calls.add('directory');
    return directoryRead?.call(cancellation) ?? Future.value(weeks);
  }

  @override
  Future<PageResult<VideoSummary>> loadPopularWeek({
    required int number,
    required RequestCancellation cancellation,
  }) {
    calls.add('week$number');
    return weekRead?.call(number, cancellation) ??
        Future.value(_page('week$number'));
  }

  @override
  Future<PageResult<VideoSummary>> loadPrecious({
    required RequestCancellation cancellation,
  }) async {
    calls.add('precious');
    return _page('precious');
  }

  @override
  Future<List<VideoCategory>> loadRankingCategories({
    required RequestCancellation cancellation,
  }) async => const [VideoCategory(id: '1008', name: '游戏')];
  @override
  Future<PageResult<VideoSummary>> loadRanking({
    required String categoryId,
    required RequestCancellation cancellation,
  }) async {
    calls.add('ranking$categoryId');
    return _page('ranking');
  }
}
