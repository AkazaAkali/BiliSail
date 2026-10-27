import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/app_recommendation_identity_repository.dart';
import 'app_recommendation_identity.dart';

final appRecommendationAuthorizationProvider = NotifierProvider.autoDispose
    .family<
      AppRecommendationAuthorizationController,
      AppRecommendationAuthorizationState,
      Object
    >(AppRecommendationAuthorizationController.new);

final class AppRecommendationAuthorizationState {
  const AppRecommendationAuthorizationState({
    this.url,
    this.message = '正在生成授权二维码',
    this.complete = false,
    this.busy = true,
  });
  final Uri? url;
  final String message;
  final bool complete, busy;
}

final class AppRecommendationAuthorizationController
    extends Notifier<AppRecommendationAuthorizationState> {
  AppRecommendationAuthorizationController(this.key);
  final Object key;
  RequestCancellation _cancellation = RequestCancellation();
  RequestCancellation? _pollCancellation;
  bool _active = true;
  Completer<void>? _resumed;
  int _generation = 0;

  void setActive(bool value) {
    _active = value;
    if (value) {
      final resumed = _resumed;
      _resumed = null;
      if (resumed != null && !resumed.isCompleted) resumed.complete();
    } else {
      _pollCancellation?.cancel();
    }
  }

  @override
  AppRecommendationAuthorizationState build() {
    ref.onDispose(() {
      _generation++;
      _cancellation.cancel();
    });
    return const AppRecommendationAuthorizationState();
  }

  Future<void> start() async {
    _cancellation.cancel();
    final cancellation = _cancellation = RequestCancellation();
    final generation = ++_generation;
    bool current() =>
        ref.mounted && !cancellation.isCancelled && generation == _generation;
    state = const AppRecommendationAuthorizationState();
    try {
      final repository = ref.read(appRecommendationIdentityRepositoryProvider);
      if (repository == null) {
        throw const AppFailure(AppFailureKind.protocol, 'App 推荐授权暂不可用');
      }
      final attempt = await repository.beginAuthorization(
        cancellation: cancellation,
      );
      if (!current()) return;
      state = AppRecommendationAuthorizationState(
        url: attempt.url,
        message: '请用当前登录账号在哔哩哔哩 App 中扫码并确认',
      );
      for (var poll = 0; poll < 60; poll++) {
        if (!current()) return;
        final pause = Completer<void>();
        final timer = Timer(const Duration(seconds: 2), pause.complete);
        cancellation.onCancel(() {
          timer.cancel();
          if (!pause.isCompleted) pause.complete();
        });
        await pause.future;
        if (!current()) return;
        while (!_active && current()) {
          final resumed = _resumed ??= Completer<void>();
          cancellation.onCancel(() {
            if (!resumed.isCompleted) resumed.complete();
          });
          await resumed.future;
        }
        if (!current()) return;
        final pollCancellation = _pollCancellation = RequestCancellation();
        cancellation.onCancel(pollCancellation.cancel);
        AppRecommendationAuthorizationStatus status;
        try {
          status = await repository.pollAuthorization(
            attempt,
            cancellation: pollCancellation,
          );
        } on AppFailure catch (failure) {
          if (failure.kind == AppFailureKind.cancelled &&
              pollCancellation.isCancelled &&
              current()) {
            poll--;
            continue;
          }
          rethrow;
        } finally {
          if (identical(_pollCancellation, pollCancellation)) {
            _pollCancellation = null;
          }
        }
        if (pollCancellation.isCancelled && current()) {
          poll--;
          continue;
        }
        if (!current()) return;
        if (status == AppRecommendationAuthorizationStatus.confirmed) {
          state = const AppRecommendationAuthorizationState(
            message: 'App 推荐授权成功',
            complete: true,
            busy: false,
          );
          return;
        }
        if (status == AppRecommendationAuthorizationStatus.expired) break;
        state = AppRecommendationAuthorizationState(
          url: attempt.url,
          message: status == AppRecommendationAuthorizationStatus.waitingConfirm
              ? '已扫码，请在哔哩哔哩 App 中确认'
              : '请用当前登录账号在哔哩哔哩 App 中扫码并确认',
        );
      }
      if (current()) {
        state = const AppRecommendationAuthorizationState(
          message: '二维码已过期，请关闭后重新授权',
          busy: false,
        );
      }
    } on AppFailure catch (failure) {
      if (current()) {
        state = AppRecommendationAuthorizationState(
          message: failure.kind == AppFailureKind.cancelled
              ? '授权已失效，请关闭后重新授权'
              : failure.message,
          busy: false,
        );
      }
    } catch (_) {
      if (current()) {
        state = const AppRecommendationAuthorizationState(
          message: '授权失败，请稍后重新尝试',
          busy: false,
        );
      }
    }
  }
}
