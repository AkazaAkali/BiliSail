import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/widgets.dart';

// Observe from application bootstrap, before native window creation. Hosts in
// widget tests also subscribe without requiring the production entry point.
final class WindowInputFocus with WidgetsBindingObserver {
  static final instance = WindowInputFocus();
  final _listeners = <VoidCallback>{};
  int? viewId;
  bool observed = false;
  int revision = 0;

  bool _initialized = false;
  bool _applicationLifetime = false;

  // Call at application bootstrap, before the explicit macOS main window.
  void initialize() {
    _applicationLifetime = true;
    _observe();
  }

  void _observe() {
    if (_initialized) return;
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
  }

  void addListener(VoidCallback listener) {
    _observe();
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (_listeners.isNotEmpty || _applicationLifetime) return;
    WidgetsBinding.instance.removeObserver(this);
    _initialized = false;
    viewId = null;
    observed = false;
    revision++;
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    observed = true;
    revision++;
    if (event.state == ViewFocusState.focused) {
      viewId = event.viewId;
    } else if (viewId == event.viewId) {
      // A late blur from A must not clear a newer focus on B.
      viewId = null;
    }
    for (final listener in _listeners.toList()) {
      listener();
    }
  }
}
