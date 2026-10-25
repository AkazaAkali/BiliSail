import 'package:bilisail/core/platform/image_export_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = NativeImageExportService();
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeImageExportService.channel, (
          call,
        ) async {
          calls.add(call);
          return call.method == 'save'
              ? r'C:\Pictures\BiliSail\test.png'
              : null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeImageExportService.channel, null);
  });

  test(
    'save and copy pass original bytes with signature-derived formats',
    () async {
      final formats = <(List<int>, String, String)>[
        ([137, 80, 78, 71, 13, 10, 26, 10], 'png', 'image/png'),
        ([255, 216, 255, 0], 'jpg', 'image/jpeg'),
        ([71, 73, 70, 56, 57, 97], 'gif', 'image/gif'),
        ([82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80], 'webp', 'image/webp'),
        ([66, 77], 'bmp', 'image/bmp'),
        (
          [0, 0, 0, 20, 102, 116, 121, 112, 97, 118, 105, 102],
          'avif',
          'image/avif',
        ),
      ];
      for (final (signature, extension, mime) in formats) {
        final bytes = Uint8List.fromList(signature);
        expect(await service.save(bytes), contains('BiliSail'));
        await service.copy(bytes);
        for (final call in calls.skip(calls.length - 2)) {
          final arguments = call.arguments as Map<Object?, Object?>;
          expect(arguments['bytes'], bytes);
          expect(arguments['extension'], extension);
          expect(arguments['mime'], mime);
          expect(
            arguments.keys,
            unorderedEquals(['bytes', 'extension', 'mime']),
          );
        }
      }
      expect(calls.map((call) => call.method), [
        for (final _ in formats) ...['save', 'copy'],
      ]);
    },
  );

  test(
    'unsupported formats and oversized data never reach native code',
    () async {
      for (final bytes in [
        Uint8List(0),
        Uint8List(16),
        Uint8List(32 * 1024 * 1024 + 1),
      ]) {
        await expectLater(service.save(bytes), throwsFormatException);
      }
      expect(calls, isEmpty);
    },
  );

  test(
    'platform capability and native failures do not report success',
    () async {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          service.supported,
          [
            TargetPlatform.windows,
            TargetPlatform.macOS,
            TargetPlatform.android,
          ].contains(platform),
        );
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            NativeImageExportService.channel,
            (_) async => null,
          );
      final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      await expectLater(service.save(png), throwsFormatException);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeImageExportService.channel, (
            _,
          ) async {
            throw PlatformException(code: 'permission_denied');
          });
      await expectLater(service.copy(png), throwsA(isA<PlatformException>()));
    },
  );
}
