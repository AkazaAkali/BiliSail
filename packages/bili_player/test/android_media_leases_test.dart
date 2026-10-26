import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bili_player/src/android_media_leases.dart';
import 'package:bili_player/bili_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.bilisail/download_storage');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'openMedia') {
            final count = calls.where((c) => c.method == 'openMedia').length;
            return {'lease': 'lease$count', 'fd': 40 + count};
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'video and external audio keep distinct leases until disposal',
    () async {
      final leases = AndroidMediaLeases();
      final video = await leases.open(
        MediaTrack(
          uri: Uri.parse('content://media/external/downloads/1'),
          requestPolicy: MediaRequestPolicy(),
        ),
      );
      final audio = await leases.open(
        MediaTrack(
          uri: Uri.parse('content://media/external/downloads/2'),
          requestPolicy: MediaRequestPolicy(),
        ),
      );
      expect(video.uri.toString(), 'fd://41');
      expect(audio.uri.toString(), 'fd://42');
      expect(calls.where((c) => c.method == 'closeMedia'), isEmpty);
      await leases.close();
      await leases.close();
      expect(
        calls
            .where((c) => c.method == 'closeMedia')
            .map((c) => c.arguments['lease']),
        ['lease1', 'lease2'],
      );
    },
  );

  test('private media needs no Android channel', () async {
    final leases = AndroidMediaLeases();
    final track = MediaTrack(
      uri: Uri.file('/private/video.mp4'),
      requestPolicy: MediaRequestPolicy(),
    );
    expect(await leases.open(track), same(track));
    await leases.close();
    expect(calls, isEmpty);
  });
}
