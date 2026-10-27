import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/features/feed/application/app_recommendation_identity.dart';
import 'package:bilisail/features/feed/domain/app_recommendation_identity_repository.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'source saves immediately and buvid validates, cancels, saves and randomizes',
    (tester) async {
      final settings = _Settings();
      final identity = _Identity();
      addTearDown(identity.events.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settings),
            appRecommendationIdentityRepositoryProvider.overrideWithValue(
              identity,
            ),
          ],
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: const Scaffold(
              body: SettingsScreen(category: SettingsCategory.recommendation),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'App 推荐'));
      await tester.pumpAndSettle();
      expect(settings.value.recommendations.source, RecommendationSource.app);
      expect(settings.value.theme, AppThemePreference.dark);
      final editor = find.widgetWithText(ListTile, 'App 推荐设备标识（buvid）');
      await tester.tap(editor);
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('app-recommendation-buvid'));
      await tester.enterText(field, 'bad');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入有效的设备标识'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(identity.device, 'fixture_device_0123456789');
      await tester.tap(editor);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'new_device_0123456789');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(identity.device, 'new_device_0123456789');
      expect(find.text('new_device_0123456789'), findsOneWidget);
      await tester.tap(editor);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '随机生成'));
      await tester.pumpAndSettle();
      expect(identity.device, 'random_device_0123456789');
      expect(find.text('random_device_0123456789'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('QR dialog closing cancels authorization generation', (
    tester,
  ) async {
    final identity = _Identity();
    addTearDown(identity.events.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(_Settings()),
          appRecommendationIdentityRepositoryProvider.overrideWithValue(
            identity,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsScreen(category: SettingsCategory.recommendation),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '扫码授权 App 推荐'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(identity.cancellation?.isCancelled, isFalse);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    expect(identity.cancellation?.isCancelled, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'QR polling pauses in the background and resumes only while the dialog exists',
    (tester) async {
      final identity = _Identity()..generateImmediately = true;
      addTearDown(identity.events.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(_Settings()),
            appRecommendationIdentityRepositoryProvider.overrideWithValue(
              identity,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SettingsScreen(category: SettingsCategory.recommendation),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '扫码授权 App 推荐'));
      await tester.pumpAndSettle();
      for (final value in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(value);
      }
      await tester.pump(const Duration(seconds: 3));
      expect(identity.polls, 0);
      for (final value in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(value);
      }
      await tester.pump();
      expect(identity.polls, 1);
      await tester.tap(find.widgetWithText(TextButton, '关闭'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(identity.polls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _Settings implements SettingsRepository {
  AppSettings value = AppSettings(theme: AppThemePreference.dark);
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    value = settings;
  }
}

final class _Identity implements AppRecommendationIdentityRepository {
  final events = StreamController<int>.broadcast();
  String device = 'fixture_device_0123456789';
  RequestCancellation? cancellation;
  bool generateImmediately = false;
  int polls = 0;
  @override
  int revision = 0;
  @override
  Stream<int> get changes => events.stream;
  @override
  Future<AppRecommendationIdentity> load() async =>
      AppRecommendationIdentity(buvid: device, canAuthorize: true);
  @override
  Future<void> setBuvid(String value) async {
    device = value;
    events.add(++revision);
  }

  @override
  Future<void> randomizeBuvid() => setBuvid('random_device_0123456789');
  @override
  Future<void> clearAuthorization() async {
    events.add(++revision);
  }

  @override
  Future<AppRecommendationAuthorization> beginAuthorization({
    required RequestCancellation cancellation,
  }) {
    this.cancellation = cancellation;
    return generateImmediately
        ? Future.value(
            AppRecommendationAuthorization(
              url: Uri.https('passport.bilibili.com', '/fixture'),
              expiresAt: DateTime.now().add(const Duration(minutes: 2)),
            ),
          )
        : Completer<AppRecommendationAuthorization>().future;
  }

  @override
  Future<AppRecommendationAuthorizationStatus> pollAuthorization(
    AppRecommendationAuthorization attempt, {
    required RequestCancellation cancellation,
  }) async {
    polls++;
    return AppRecommendationAuthorizationStatus.waitingScan;
  }
}
