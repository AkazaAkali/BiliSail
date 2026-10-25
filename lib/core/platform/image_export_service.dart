import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/image_export_service.dart';

final class NativeImageExportService implements ImageExportService {
  const NativeImageExportService();
  static const channel = MethodChannel('bilisail/image_export');

  @override
  bool get supported =>
      !kIsWeb &&
      const [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.android,
      ].contains(defaultTargetPlatform);

  Map<String, Object> _arguments(Uint8List bytes) {
    if (!supported) throw UnsupportedError('Image export unavailable');
    if (bytes.isEmpty || bytes.length > 32 * 1024 * 1024) {
      throw const FormatException('Invalid image size');
    }
    // Use the actual file signature: CDN URLs may have no extension, or end in
    // a different format. Never use a remote path as a local filename.
    bool starts(List<int> signature, [int offset = 0]) =>
        bytes.length >= signature.length + offset &&
        listEquals(bytes.sublist(offset, offset + signature.length), signature);
    final (extension, mime) = switch (bytes) {
      _ when starts([137, 80, 78, 71, 13, 10, 26, 10]) => ('png', 'image/png'),
      _ when starts([255, 216, 255]) => ('jpg', 'image/jpeg'),
      _ when starts([71, 73, 70, 56]) => ('gif', 'image/gif'),
      _ when starts([82, 73, 70, 70]) && starts([87, 69, 66, 80], 8) => (
        'webp',
        'image/webp',
      ),
      _ when starts([66, 77]) => ('bmp', 'image/bmp'),
      _
          when starts([102, 116, 121, 112], 4) &&
              (starts([97, 118, 105, 102], 8) ||
                  starts([97, 118, 105, 115], 8)) =>
        ('avif', 'image/avif'),
      _ => throw const FormatException('Unsupported image format'),
    };
    return {'bytes': bytes, 'extension': extension, 'mime': mime};
  }

  @override
  Future<String> save(Uint8List bytes) async {
    final path = await channel
        .invokeMethod<String>('save', _arguments(bytes))
        .timeout(const Duration(seconds: 30));
    if (path == null || path.isEmpty) {
      throw const FormatException('Missing saved image location');
    }
    return path;
  }

  @override
  Future<void> copy(Uint8List bytes) => channel
      .invokeMethod<void>('copy', _arguments(bytes))
      .timeout(const Duration(seconds: 30));
}
