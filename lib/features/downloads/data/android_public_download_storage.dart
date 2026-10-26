import 'dart:async';

import 'package:flutter/services.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/download_models.dart';
import '../domain/public_download_storage.dart';

final class AndroidPublicDownloadStorage implements PublicDownloadStorage {
  const AndroidPublicDownloadStorage();
  static const _channel = MethodChannel('dev.bilisail/download_storage');

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw AppFailure(
        e.code == 'permission'
            ? AppFailureKind.permission
            : AppFailureKind.storage,
        e.message ?? '公共下载位置不可用，请重新授权或连接存储设备',
      );
    }
  }

  Map<String, Object?> _task(DownloadTask task) => {
    'id': task.id,
    'scope': task.scope,
    'destination': task.publicDestination,
    'uris': task.publicFiles,
  };

  @override
  Future<bool> chooseDestination({bool force = false}) async =>
      await _call<bool>('choose', {'force': force}) ?? false;

  @override
  Future<String> destination() async {
    final value = await _call<String>('destination');
    if (value == null) {
      throw const AppFailure(AppFailureKind.permission, '请先选择公共下载保存位置');
    }
    return value;
  }

  @override
  Future<Map<String, String>> publish(
    DownloadTask task,
    Map<String, String> files,
    RequestCancellation cancellation,
  ) async {
    var finished = false;
    cancellation.onCancel(() {
      if (!finished)
        unawaited(_call<void>('cancel', _task(task)).catchError((Object _) {}));
    });
    try {
      if (cancellation.isCancelled) {
        throw const AppFailure(AppFailureKind.cancelled, '保存已取消');
      }
      final result = await _call<Map<Object?, Object?>>('publish', {
        ..._task(task),
        'files': files,
      });
      return result!.cast<String, String>();
    } finally {
      finished = true;
    }
  }

  @override
  Future<void> verify(DownloadTask task) => _call<void>('verify', _task(task));
  @override
  Future<void> delete(DownloadTask task) => _call<void>('delete', _task(task));
}
