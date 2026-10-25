import 'dart:async';

import 'support/multi_view_binding.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // The Flutter tool initializes its default integration binding before calling
  // test.main. Install the real-engine-ID variant at the standard config hook.
  MultiViewIntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await testMain();
}
