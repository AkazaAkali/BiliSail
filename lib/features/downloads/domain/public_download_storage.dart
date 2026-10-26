import '../../../domain/request_cancellation.dart';
import 'download_models.dart';

final class DownloadFolder {
  const DownloadFolder({required this.path, required this.name});
  final String path;
  final String name;
}

final class DownloadFolderListing {
  DownloadFolderListing({
    this.directory,
    this.parent,
    required List<DownloadFolder> folders,
    this.truncated = false,
  }) : folders = List.unmodifiable(folders);
  final DownloadFolder? directory;
  final String? parent;
  final List<DownloadFolder> folders;
  final bool truncated;
}

/// Selected shared folders and legacy provider URIs retain private staging.
abstract interface class PublicDownloadStorage {
  Future<bool> hasDestination();
  Future<bool> requestDirectoryAccess();
  Future<DownloadFolderListing> listDirectories(String? directory);
  Future<void> chooseDestination(String directory);
  Future<String> destination();
  Future<Map<String, String>> publish(
    DownloadTask task,
    Map<String, String> files,
    RequestCancellation cancellation,
  );
  Future<void> verify(DownloadTask task);
  Future<void> delete(DownloadTask task);
}
