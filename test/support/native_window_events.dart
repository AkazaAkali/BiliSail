import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> sendNativeWindowBack(WidgetTester tester, int viewId) async {
  final replied = Completer<void>();
  tester.binding.channelBuffers.push(
    'bilisail/desktop_window',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('back', {'viewId': viewId}),
    ),
    (_) => replied.complete(),
  );
  await replied.future;
}
