import 'package:bili_mux/src/native_library_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux packages load the mux next to their executable', () {
    for (final directory in [
      '/tmp/.mount_BiliSail/usr/bin',
      '/app/usr/bin',
      '/home/user/My apps/BiliSail',
    ]) {
      expect(
        nativeMuxLibraryPath('linux', Uri.file('$directory/bilisail')),
        '$directory/lib/libbili_mux.so',
      );
    }
  });

  test('Apple platforms use their distinct embedded framework layouts', () {
    expect(
      nativeMuxLibraryPath('ios', Uri.file('/private/app/Runner.app/Runner')),
      '/private/app/Runner.app/Frameworks/BiliMux.framework/BiliMux',
    );
    expect(
      nativeMuxLibraryPath(
        'macos',
        Uri.file('/Applications/BiliSail.app/Contents/MacOS/BiliSail'),
      ),
      '/Applications/BiliSail.app/Contents/Frameworks/BiliMux.framework/BiliMux',
    );
  });

  test('Windows and Android retain their existing asset layouts', () {
    expect(
      nativeMuxLibraryPath('windows', Uri.parse('file:///C:/BiliSail/app.exe')),
      r'C:\BiliSail\bili_mux.dll',
    );
    expect(
      nativeMuxLibraryPath('android', Uri.file('/system/bin/app_process64')),
      'libbili_mux.so',
    );
    expect(nativeMuxLibraryPath('unsupported', Uri.file('/app')), isNull);
  });
}
