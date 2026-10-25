/// Resolve assets relative to the executable, including an AppImage mount or
/// Flatpak's /app tree. Never use the working directory or a host system mux.
String? nativeMuxLibraryPath(String operatingSystem, Uri executable) =>
    switch (operatingSystem) {
      'windows' => executable.resolve('bili_mux.dll').toFilePath(windows: true),
      'android' => 'libbili_mux.so',
      'linux' =>
        executable.resolve('lib/libbili_mux.so').toFilePath(windows: false),
      'ios' =>
        executable
            .resolve('Frameworks/BiliMux.framework/BiliMux')
            .toFilePath(windows: false),
      'macos' =>
        executable
            .resolve('../Frameworks/BiliMux.framework/BiliMux')
            .toFilePath(windows: false),
      _ => null,
    };
