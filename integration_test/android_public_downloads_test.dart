import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Opt in on an Android 10+ device: creates then deletes two small public files.
/// SAF picker and removable-provider behavior remain manual device checks.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'MediaStore publication and exact URI deletion boundary',
    (tester) async {
      const channel = MethodChannel('dev.bilisail/download_storage');
      final id = List.generate(
        16,
        (_) => Random.secure().nextInt(256),
      ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final docs = await getApplicationDocumentsDirectory();
      final staging = await Directory(
        '${docs.path}/BiliSail/offline/storage-test/$id',
      ).create(recursive: true);
      final files = <String, String>{};
      final args = <String, Object?>{
        'id': id,
        'scope': 'storage-test',
        'destination': 'downloads',
      };
      try {
        for (final name in ['video.m4s', 'audio.m4s']) {
          final file = await File(
            '${staging.path}/$name',
          ).writeAsBytes([1, 2, 3]);
          files[name] = file.path;
        }
        final uris = await channel.invokeMapMethod<String, String>('publish', {
          ...args,
          'files': files,
        });
        expect(uris!.keys, containsAll(['video.m4s', 'audio.m4s']));
        await channel.invokeMethod<void>('verify', {...args, 'uris': uris});
        final opened = await channel.invokeMapMethod<String, Object?>(
          'openMedia',
          {'uri': uris['video.m4s']},
        );
        expect(opened!['fd'], isA<int>());
        await channel.invokeMethod<void>('closeMedia', {
          'lease': opened['lease'],
        });
        final repeated = await channel.invokeMapMethod<String, String>(
          'publish',
          {...args, 'files': files},
        );
        expect(repeated, uris);
        await expectLater(
          channel.invokeMethod<void>('verify', {
            ...args,
            'uris': {'video.m4s': 'content://media/external/downloads/0'},
          }),
          throwsA(isA<PlatformException>()),
        );
      } finally {
        await channel.invokeMethod<void>('delete', args);
        await staging.delete(recursive: true);
      }
    },
    skip:
        !Platform.isAndroid ||
        !const bool.fromEnvironment('ANDROID_PUBLIC_STORAGE_TEST'),
  );
}
