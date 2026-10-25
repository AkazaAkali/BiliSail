import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class MultiViewIntegrationTestWidgetsFlutterBinding
    extends IntegrationTestWidgetsFlutterBinding {
  static MultiViewIntegrationTestWidgetsFlutterBinding? _instance;

  static MultiViewIntegrationTestWidgetsFlutterBinding ensureInitialized() =>
      _instance ??= MultiViewIntegrationTestWidgetsFlutterBinding();

  late final _nativeDispatcher = _NativeEngineDispatcher();

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
