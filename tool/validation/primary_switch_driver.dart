import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    final result = data['primarySwitch'] as Map<String, Object?>;
    final label = result['label']! as String;
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(label)) {
      throw ArgumentError('Invalid profile label');
    }
    final file = File('build/validation/primary-switch-$label.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result),
    );
  },
);
