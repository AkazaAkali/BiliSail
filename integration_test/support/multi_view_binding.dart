import 'dart:ui' show AppExitResponse, AppExitType, PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class MultiViewIntegrationTestWidgetsFlutterBinding
    extends IntegrationTestWidgetsFlutterBinding {
  static MultiViewIntegrationTestWidgetsFlutterBinding? _instance;

  static MultiViewIntegrationTestWidgetsFlutterBinding ensureInitialized() =>
      _instance ??= MultiViewIntegrationTestWidgetsFlutterBinding();

  late final _nativeDispatcher = _NativeEngineDispatcher();
  bool forwardNativeExitRequests = false;

  @override
  Future<AppExitResponse> exitApplication(
    AppExitType exitType, [
    int exitCode = 0,
  ]) async {
    if (!forwardNativeExitRequests) {
      return super.exitApplication(exitType, exitCode);
    }
    final response = await SystemChannels.platform
        .invokeMethod<Map<String, Object?>>('System.exitApplication', {
          'type': exitType.name,
          'exitCode': exitCode,
        });
    return response?['response'] == 'exit'
        ? AppExitResponse.exit
        : AppExitResponse.cancel;
  }

  @override
  TestPlatformDispatcher get platformDispatcher => _nativeDispatcher;
}

class _NativeEngineDispatcher extends TestPlatformDispatcher {
  _NativeEngineDispatcher()
    : super(platformDispatcher: PlatformDispatcher.instance);

  // TestPlatformDispatcher uses a fake ID of 1, which cannot be passed to the
  // real engine's windowing FFI. Other test APIs retain their normal wrappers.
  @override
  int? get engineId => PlatformDispatcher.instance.engineId;
}
