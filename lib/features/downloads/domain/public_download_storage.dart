import '../../../domain/request_cancellation.dart';
import 'download_models.dart';

/// Public media lives behind provider URIs; private staging retains file semantics.
abstract interface class PublicDownloadStorage {
  Future<bool> chooseDestination({bool force = false});
  Future<String> destination();
  Future<Map<String, String>> publish(
    DownloadTask task,
    Map<String, String> files,
    RequestCancellation cancellation,
  );
  Future<void> verify(DownloadTask task);
  Future<void> delete(DownloadTask task);
}
