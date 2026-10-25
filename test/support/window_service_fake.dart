import 'package:bilisail/core/platform/window_service.dart';

// Native message routing is exercised with mocked platform channels on every
// test host, including Linux where production title bars are not installed.
class FakePlaybackWindowService extends WindowService {
  FakePlaybackWindowService({
    required super.viewId,
    required super.setFullScreen,
    required super.activate,
    super.isAvailable,
    this.nativeTitleBar = true,
  }) : super.forView();

  final bool nativeTitleBar;

  @override
  bool get hasNativePlaybackTitleBar => nativeTitleBar;
}
