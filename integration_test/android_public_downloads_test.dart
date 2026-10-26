import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Opt in: creates then deletes small files. Shared-folder tests require storage
/// access already granted and an explicit ANDROID_DOWNLOAD_DIRECTORY.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const selectedFolder = String.fromEnvironment('ANDROID_DOWNLOAD_DIRECTORY');
  testWidgets(
    'selected shared folder publishes, reopens and deletes exact owned files',
    (tester) async {
      const channel = MethodChannel('dev.bilisail/download_storage');
      expect(await channel.invokeMethod<bool>('requestAccess'), true);
      final listing = await channel.invokeMapMethod<String, Object?>(
        'listDirectories',
        {'directory': selectedFolder},
      );
      expect(listing!['directory'], containsPair('path', selectedFolder));
      await channel.invokeMethod<void>('choose', {'directory': selectedFolder});
      expect(await channel.invokeMethod<bool>('hasDestination'), true);
      final destination = await channel.invokeMethod<String>('destination');
      expect(destination, File(selectedFolder).uri.toString());
      final id = List.generate(
        16,
        (_) => Random.secure().nextInt(256),
      ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final docs = await getApplicationDocumentsDirectory();
      final staging = await Directory(
        '${docs.path}/BiliSail/offline/storage-test/$id',
      ).create(recursive: true);
      final sentinel = File('$selectedFolder/.bilisail-test-$id');
      final args = <String, Object?>{
        'id': id,
        'scope': 'storage-test',
        'destination': destination,
      };
      try {
        await sentinel.writeAsString('unrelated');
        final files = <String, String>{};
        for (final name in ['video.m4s', 'audio.m4s']) {
          files[name] = (await File(
            '${staging.path}/$name',
          ).writeAsBytes([1, 2, 3])).path;
        }
        final uris = await channel.invokeMapMethod<String, String>('publish', {
          ...args,
          'files': files,
        });
        expect(uris!.keys, containsAll(['video.m4s', 'audio.m4s']));
        await channel.invokeMethod<void>('verify', {...args, 'uris': uris});
        for (final uri in uris.values) {
          expect(await File.fromUri(Uri.parse(uri)).readAsBytes(), [1, 2, 3]);
        }
        expect(
          await channel.invokeMapMethod<String, String>('publish', {
            ...args,
            'files': files,
          }),
          uris,
        );
        await expectLater(
          channel.invokeMethod<void>('verify', {
            ...args,
            'uris': {'video.m4s': sentinel.uri.toString()},
          }),
          throwsA(isA<PlatformException>()),
        );
        await channel.invokeMethod<void>('delete', args);
        for (final uri in uris.values) {
          expect(await File.fromUri(Uri.parse(uri)).exists(), false);
        }
        expect(await sentinel.readAsString(), 'unrelated');
      } finally {
        await channel.invokeMethod<void>('delete', args);
        if (await sentinel.exists()) await sentinel.delete();
        await staging.delete(recursive: true);
      }
    },
    skip:
        !Platform.isAndroid ||
        selectedFolder.isEmpty ||
        !const bool.fromEnvironment('ANDROID_PUBLIC_STORAGE_TEST'),
  );
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
          final file = await File('${staging.path}/$name')
              .writeAsBytes([1, 2, 3]);
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
