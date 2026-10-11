import 'dart:async';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/high_energy_trend.dart';

/// Process-local, account-epoch isolated LRU. No raw response or timers retained.
final class HighEnergyCache {
  HighEnergyCache(this.requests, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final ApiRequests requests;
  final DateTime Function() _now;
  final _entries = <String, _Entry>{};
  final _flights = <String, _Flight>{};
  RequestCancellation? _lifetime;
  int _bytes = 0;

  Future<HighEnergyTrend?> load(
    String identity,
    RequestCancellation consumer,
    Future<HighEnergyTrend?> Function(RequestCancellation) read,
  ) async {
    if (consumer.isCancelled) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
    if (_lifetime == null || _lifetime!.isCancelled) {
      final lifetime = RequestCancellation();
      _lifetime = lifetime;
      lifetime.onCancel(() {
        _entries.clear();
        _bytes = 0;
        for (final flight in _flights.values.toList()) {
          flight.token.cancel();
        }
        _flights.clear();
      });
      requests.trackLifetime(lifetime);
    }
    final key = '${requests.sessionEpoch}:$identity';
    final cached = _entries.remove(key);
    if (cached != null) {
      if (_now().isBefore(cached.expires)) {
        _entries[key] = cached;
        return cached.value;
      }
      _bytes -= cached.bytes;
    }
    var flight = _flights[key];
    if (flight == null || flight.token.isCancelled) {
      final created = _Flight();
      flight = created;
      _flights[key] = created;
      final epoch = requests.sessionEpoch;
      created.future = () async {
        try {
          final value = await read(created.token);
          if (!created.token.isCancelled && epoch == requests.sessionEpoch) {
            _remember(key, value);
          }
          return value;
        } on AppFailure catch (failure) {
          if (failure.kind != AppFailureKind.cancelled &&
              !created.token.isCancelled &&
              epoch == requests.sessionEpoch) {
            _remember(key, null);
          }
          rethrow;
        } finally {
          if (identical(_flights[key], created)) _flights.remove(key);
        }
      }();
    }
    final active = flight;
    active.consumers++;
    final cancelled = Completer<HighEnergyTrend?>();
    consumer.onCancel(() {
      if (!cancelled.isCompleted) {
        cancelled.completeError(
          const AppFailure(AppFailureKind.cancelled, '请求已取消'),
        );
      }
    });
    try {
      final result = await Future.any([active.future, cancelled.future]);
      if (consumer.isCancelled || active.token.isCancelled) {
        throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
      }
      return result;
    } finally {
      // Complete the small cancellation waiter so it retains no pending future.
      if (!cancelled.isCompleted) cancelled.complete(null);
      if (--active.consumers == 0) active.token.cancel();
    }
  }

  void _remember(String key, HighEnergyTrend? value) {
    final previous = _entries.remove(key);
    if (previous != null) _bytes -= previous.bytes;
    final entry = _Entry(
      value,
      _now().add(Duration(minutes: value == null ? 10 : 30)),
    );
    _entries[key] = entry;
    _bytes += entry.bytes;
    while (_entries.length > 32 || _bytes > 1024 * 1024) {
      _bytes -= _entries.remove(_entries.keys.first)!.bytes;
    }
  }
}

final class _Flight {
  final token = RequestCancellation();
  late Future<HighEnergyTrend?> future;
  int consumers = 0;
}

final class _Entry {
  _Entry(this.value, this.expires);
  final HighEnergyTrend? value;
  final DateTime expires;
  int get bytes => 128 + (value?.points.length ?? 0) * 48;
}
