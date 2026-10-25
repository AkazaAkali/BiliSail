import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/native_window_events.dart';
import '../../support/window_service_fake.dart';

void main() {
  const channel = MethodChannel('bilisail/desktop_window');

  testWidgets('unsupported native Back fails without queuing a stale event', (
    tester,
  ) async {
    channel.setMethodCallHandler(null);
    addTearDown(() => channel.setMethodCallHandler(null));
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    final window = FakePlaybackWindowService(
      viewId: 42,
      setFullScreen: (_) async {},
      activate: () async {},
      nativeTitleBar: false,
    );
    var backs = 0;
    await window.bindTitleBarBack(owner: Object(), onBack: () => backs++);
    expect(calls, isEmpty);
    await expectLater(
      sendNativeWindowBack(tester, 42),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Native Back handler is not registered for view 42'),
        ),
      ),
    );
    channel.setMethodCallHandler((_) async => backs++);
    await tester.pump();
    expect(backs, 0);
  });

  testWidgets('native Back surfaces an error reply', (tester) async {
    channel.setMethodCallHandler((_) async {
      throw PlatformException(code: 'back_failed');
    });
    addTearDown(() => channel.setMethodCallHandler(null));
    await expectLater(
      sendNativeWindowBack(tester, 42),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'back_failed',
        ),
      ),
    );
  });
}
