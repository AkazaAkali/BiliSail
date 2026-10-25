import 'dart:async';

import 'package:bilisail/app/workspace_playback_window.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/native_window_events.dart';

void main() {
  testWidgets('native Back respects modal isolation and adds no content row', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    for (final channel in ['bilisail/desktop_window', 'bilisail/text_input']) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel(channel),
          null,
        ),
      );
    }
    var backs = 0;
    final service = WindowService.forView(
      viewId: 42,
      setFullScreen: (_) async {},
      activate: () async {},
    );
    await tester.pumpWidget(
      WindowServiceScope(
        service: service,
        child: WorkspacePlaybackWindow(
          shortcuts: const ShortcutSettings.defaults(),
          theme: ThemeData(),
          onBack: () => backs++,
          onClose: () {},
          onActivateBrowser: () {},
          child: const SizedBox.expand(key: ValueKey('playback-content')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('playback-window-back')), findsNothing);
    expect(find.byKey(const ValueKey('playback-window-close')), findsNothing);
    expect(find.text('浏览窗口'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('playback-content'))),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    expect(calls.any((call) => call.method == 'setBackButton'), isTrue);
    await sendNativeWindowBack(tester, 42);
    expect(backs, 1);

    unawaited(
      showDialog<void>(
        context: tester.element(find.byKey(const ValueKey('playback-content'))),
        builder: (_) => const AlertDialog(content: Text('modal')),
      ),
    );
    await tester.pumpAndSettle();
    await sendNativeWindowBack(tester, 42);
    expect(backs, 1);
    expect(find.text('modal'), findsOneWidget);
    Navigator.of(tester.element(find.text('modal'))).pop();
    await tester.pumpAndSettle();
    await sendNativeWindowBack(tester, 42);
    expect(backs, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await sendNativeWindowBack(tester, 42);
    expect(backs, 2);
    expect(calls.any((call) => call.method == 'removeBackButton'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
