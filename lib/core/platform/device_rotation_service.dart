import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_rotation.dart';

final deviceRotationProvider = Provider<Stream<DeviceRotation>>(
  (ref) => DeviceRotationService.events,
);

/// Shared broadcast source: hidden playback tabs must not replace the native
/// channel's single listener. No sensor work occurs without subscribers.
class DeviceRotationService {
  static const _channel = EventChannel('bilisail/device_orientation');
  static final Stream<DeviceRotation> events =
      Platform.isAndroid || Platform.isIOS
      ? _channel.receiveBroadcastStream().map((event) {
          final values = event is Map ? event : const <Object?, Object?>{};
          return DeviceRotation(
            switch (values['orientation']) {
              'portrait' => DevicePosture.portrait,
              'landscape' => DevicePosture.landscape,
              _ => DevicePosture.unknown,
            },
            autoRotate: values['autoRotate'] == true,
            supported: values['supported'] == true,
          );
        })
      : const Stream.empty();
}
