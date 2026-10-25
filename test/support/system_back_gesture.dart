import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sends the same platform-channel events as Android's predictive back callback.
Future<Object?> systemBackGesture(
  WidgetTester tester,
  String method, {
  double progress = 0,
  SwipeEdge edge = SwipeEdge.left,
}) async {
  Object? result;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, {
        'touchOffset': [edge == SwipeEdge.left ? 1.0 : 389.0, 300.0],
        'progress': progress,
        'swipeEdge': edge.index,
      }),
    ),
    (data) {
      if (data != null) {
        result = const StandardMethodCodec().decodeEnvelope(data);
      }
    },
  );
  return result;
}
