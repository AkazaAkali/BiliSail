import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> sendNativeWindowBack(WidgetTester tester, int viewId) async {
  await _sendNativeWindowAction(tester, viewId, 'back');
}

Future<void> sendNativeWindowHome(WidgetTester tester, int viewId) async {
  await _sendNativeWindowAction(tester, viewId, 'home');
}

Future<void> _sendNativeWindowAction(
  WidgetTester tester,
  int viewId,
  String action,
) async {
  const codec = StandardMethodCodec();
  // The test messenger replies with null when there is no handler, whereas
  // ChannelBuffers queues the message until a listener arrives and can hang.
  final response = await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage(
        'bilisail/desktop_window',
        codec.encodeMethodCall(MethodCall(action, {'viewId': viewId})),
        null,
      );
  if (response == null) {
    throw StateError('Native Back handler is not registered for view $viewId.');
  }
  codec.decodeEnvelope(response);
}
