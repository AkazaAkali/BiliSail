import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/common.dart';

/// Host-side companion for windows_high_energy_test.dart. Resource samples and
/// forced GC happen in the one-second gaps outside measured frame intervals.
Future<void> main() async {
  final driver = await FlutterDriver.connect();
  final samples = <Map<String, Object?>>[];
  var done = false;
  final directory = Platform.environment['BILI_HIGH_ENERGY_OUTPUT'];
  Future<void> monitor() async {
    if (driver is! VMServiceFlutterDriver || directory == null) return;
    final vm = await driver.serviceClient.getVM();
    final isolateId = driver.appIsolate.id;
    if (vm.pid == null || isolateId == null) {
      throw StateError('Profile VM identity unavailable');
    }
    String? previous;
    while (!done) {
      final file = File('$directory/phase.json');
      if (await file.exists()) {
        final data = await file.readAsString();
        if (data != previous && data.isNotEmpty) {
          Object? decoded;
          try {
            decoded = jsonDecode(data);
          } on FormatException {
            // The test may be in the middle of replacing the short phase file.
          }
          if (decoded is Map<String, Object?>) {
            previous = data;
            final allocation = await driver.serviceClient.getAllocationProfile(
              isolateId,
              gc: true,
            );
            final result = await Process.run('powershell', [
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              '\$taskProcess = Get-Process -Id ${vm.pid}; '
                  '@{cpuSeconds=\$taskProcess.TotalProcessorTime.TotalSeconds; '
                  'rss=\$taskProcess.WorkingSet64; processors=[Environment]::ProcessorCount} '
                  '| ConvertTo-Json -Compress',
            ]);
            if (result.exitCode != 0) {
              throw StateError('Profile process unavailable');
            }
            samples.add({
              ...decoded,
              'time': DateTime.now().toUtc().toIso8601String(),
              'memory': allocation.memoryUsage?.toJson(),
              'process': jsonDecode(result.stdout as String),
            });
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  final monitoring = monitor();
  late Response response;
  try {
    response = Response.fromJson(
      await driver.requestData(null, timeout: const Duration(minutes: 10)),
    );
  } finally {
    done = true;
    try {
      await monitoring;
    } finally {
      await driver.close();
    }
  }
  if (directory != null) {
    await File('$directory/resources.json').writeAsString(jsonEncode(samples));
  }
  if (!response.allTestsPassed) {
    stderr.writeln(response.formattedFailureDetails);
  }
  exit(response.allTestsPassed ? 0 : 1);
}
