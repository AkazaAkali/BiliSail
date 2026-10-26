import 'dart:async';

import 'package:bilisail/core/platform/window_brightness_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bilisail/window_brightness');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('reads the native brightness and rejects invalid results', () async {
    final service = WindowBrightnessService();
    for (final value in <double?>[.4, null, -1, 2, double.nan]) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      if (value == .4) {
        expect(await service.read(), .4);
      } else {
        await expectLater(service.read(), throwsFormatException);
      }
    }
  });

  test(
    'reset follows pending writes, and failures do not block restoration',
    () async {
      final service = WindowBrightnessService();
      final gate = Completer<void>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'set') {
          await gate.future;
          throw PlatformException(code: 'brightness_failed');
        }
        return null;
      });
      final write = service.set(.4);
      final failed = expectLater(write, throwsA(isA<PlatformException>()));
      final reset = service.reset();
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((call) => call.method), ['set']);
      gate.complete();
      await failed;
      await reset;
      expect(calls.map((call) => call.method), ['set', 'reset']);
      final first = calls.first.arguments as Map<Object?, Object?>;
      final last = calls.last.arguments as Map<Object?, Object?>;
      expect(first['value'], .4);
      expect(last['owner'], first['owner']);
    },
  );
}
