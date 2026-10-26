import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Owns a temporary Android window override, without changing system settings.
class WindowBrightnessService {
  static const _channel = MethodChannel('bilisail/window_brightness');
  static int _nextOwner = DateTime.now().microsecondsSinceEpoch;
  final int _owner = ++_nextOwner;
  Future<void> _writes = Future<void>.value();

  bool get isNative => Platform.isAndroid;

  Future<double> read() async {
    final value = await _channel
        .invokeMethod<double>('get')
        .timeout(const Duration(seconds: 2));
    if (value == null || !value.isFinite || value < 0 || value > 1) {
      throw const FormatException('Invalid window brightness');
    }
    return value;
  }

  Future<void> set(double value) => _write('set', value: value);
  Future<void> reset() => _write('reset');

  Future<void> _write(String method, {double? value}) {
    final result = _writes.then(
      (_) => _channel
          .invokeMethod<void>(method, {'owner': _owner, 'value': ?value})
          .timeout(const Duration(seconds: 2)),
    );
    _writes = result.then((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
