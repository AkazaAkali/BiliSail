// Match the application's pinned experimental desktop windowing environment.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter/src/foundation/_features.dart' as flutter_features;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void enableDesktopWindowing(WidgetTester tester) {
  final previous = flutter_features.isWindowingEnabled;
  flutter_features.isWindowingEnabled = true;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    flutter_features.isWindowingEnabled = previous;
  });
}
