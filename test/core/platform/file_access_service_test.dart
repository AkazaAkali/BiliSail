import 'dart:io';

import 'package:bilisail/core/platform/file_access_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  test(
    'Linux downloads use persistent app storage instead of host Documents',
    () async {
      final calls = <String>[];
      final support = Directory.systemTemp.absolute.path;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return support;
      });
      addTearDown(() {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      });

      final directory = await const FileAccessService()
          .defaultDownloadDirectory();
      expect(calls, [
        Platform.isLinux
            ? 'getApplicationSupportDirectory'
            : 'getApplicationDocumentsDirectory',
      ]);
      expect(
        directory,
        Platform.isLinux
            ? path.join(support, 'offline')
            : path.join(support, 'BiliSail', 'offline'),
      );
    },
  );
}
