import 'dart:async';

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
      expect(find.textContaining('请重新登录'), findsOneWidget);
      expect(find.text('扫码授权 App 推荐'), findsNothing);
      expect(find.text('更新登录'), findsNothing);
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
  @override
  int revision = 0;
  @override
  Stream<int> get changes => events.stream;
  @override
  Future<AppRecommendationIdentity> load() async =>
      AppRecommendationIdentity(buvid: device);
  @override
  Future<void> setBuvid(String value) async {
    device = value;
    events.add(++revision);
  }

  @override
  Future<void> randomizeBuvid() => setBuvid('random_device_0123456789');
}
