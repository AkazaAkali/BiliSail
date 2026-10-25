import 'dart:typed_data';

abstract interface class ImageExportService {
  bool get supported;
  Future<String> save(Uint8List bytes);
  Future<void> copy(Uint8List bytes);
}

final class UnsupportedImageExportService implements ImageExportService {
  const UnsupportedImageExportService();
  @override
  bool get supported => false;
  @override
  Future<String> save(Uint8List bytes) =>
      Future.error(UnsupportedError('Image export unavailable'));
  @override
  Future<void> copy(Uint8List bytes) =>
      Future.error(UnsupportedError('Image export unavailable'));
}
