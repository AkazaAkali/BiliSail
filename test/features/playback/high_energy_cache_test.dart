import 'dart:async';

import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/playback/data/high_energy_cache.dart';
import 'package:bilisail/features/playback/domain/high_energy_trend.dart';
import 'package:flutter_test/flutter_test.dart';

final _trend = HighEnergyTrend(
  step: const Duration(seconds: 1),
  span: const Duration(seconds: 4),
  points: const [
    HighEnergyPoint(0, 0),
    HighEnergyPoint(.5, 1),
    HighEnergyPoint(1, .3),
  ],
);

void main() {
  test(
    'failed optional reads are negatively cached; cancellation is not',
    () async {
      var now = DateTime(2026);
      final cache = HighEnergyCache(ApiRequests(), now: () => now);
      var calls = 0;
      Future<HighEnergyTrend?> fail(RequestCancellation _) async {
        calls++;
        throw const AppFailure(AppFailureKind.network, 'failed');
      }

      await expectLater(
        cache.load('error', RequestCancellation(), fail),
        throwsA(isA<AppFailure>()),
      );
      expect(await cache.load('error', RequestCancellation(), fail), isNull);
      expect(calls, 1);
      now = now.add(const Duration(minutes: 11));
      await expectLater(
        cache.load('error', RequestCancellation(), fail),
        throwsA(isA<AppFailure>()),
      );
      expect(calls, 2);
    },
  );
  test('span guard rejects a whole-video curve for a single part', () {
    expect(_trend.matchesDuration(const Duration(seconds: 4)), isTrue);
    expect(_trend.matchesDuration(Duration.zero), isFalse);
    expect(_trend.matchesDuration(const Duration(seconds: 40)), isFalse);
  });
  test('shared reads cancel only when the last consumer leaves', () async {
    final cache = HighEnergyCache(ApiRequests());
    final gate = Completer<HighEnergyTrend?>();
    late RequestCancellation wire;
    var calls = 0;
    Future<HighEnergyTrend?> read(RequestCancellation token) {
      calls++;
      wire = token;
      return gate.future;
    }

    final first = RequestCancellation(), second = RequestCancellation();
    final a = cache.load('same', first, read);
    final b = cache.load('same', second, read);
    final rejected = expectLater(a, throwsA(isA<AppFailure>()));
    first.cancel();
    await rejected;
    expect(wire.isCancelled, isFalse);
    expect(calls, 1);
    gate.complete(_trend);
    expect(await b, same(_trend));
    expect(await cache.load('same', RequestCancellation(), read), same(_trend));
    expect(calls, 1);
  });
  test(
    'all consumers leaving and account changes cancel pending reads',
    () async {
      final requests = ApiRequests();
      final cache = HighEnergyCache(requests);
      final gates = <Completer<HighEnergyTrend?>>[];
      final wires = <RequestCancellation>[];
      Future<HighEnergyTrend?> read(RequestCancellation token) {
        wires.add(token);
        final gate = Completer<HighEnergyTrend?>();
        gates.add(gate);
        return gate.future;
      }

      final consumer = RequestCancellation();
      final first = cache.load('one', consumer, read);
      final rejected = expectLater(first, throwsA(isA<AppFailure>()));
      consumer.cancel();
      await rejected;
      expect(wires.first.isCancelled, isTrue);
      gates.first.complete(_trend);
      await Future<void>.delayed(Duration.zero);
      final second = cache.load('one', RequestCancellation(), read);
      final accountRejected = expectLater(second, throwsA(isA<AppFailure>()));
      requests.advanceSession();
      expect(wires.last.isCancelled, isTrue);
      gates.last.complete(_trend);
      await accountRejected;
      final third = cache.load('one', RequestCancellation(), read);
      expect(gates, hasLength(3));
      gates.last.complete(_trend);
      await third;
    },
  );
  test(
    'LRU has 32 entries, TTLs expire and account changes drop successes',
    () async {
      final requests = ApiRequests();
      var now = DateTime(2026);
      final cache = HighEnergyCache(requests, now: () => now);
      var calls = 0;
      Future<HighEnergyTrend?> read(RequestCancellation _) async {
        calls++;
        return _trend;
      }

      for (var i = 0; i < 33; i++) {
        await cache.load('$i', RequestCancellation(), read);
      }
      await cache.load('32', RequestCancellation(), read);
      expect(calls, 33);
      await cache.load('0', RequestCancellation(), read);
      expect(calls, 34);
      now = now.add(const Duration(minutes: 31));
      await cache.load('0', RequestCancellation(), read);
      expect(calls, 35);
      requests.advanceSession();
      await cache.load('0', RequestCancellation(), read);
      expect(calls, 36);
      Future<HighEnergyTrend?> empty(RequestCancellation _) async {
        calls++;
        return null;
      }

      await cache.load('empty', RequestCancellation(), empty);
      now = now.add(const Duration(minutes: 9));
      await cache.load('empty', RequestCancellation(), empty);
      expect(calls, 37);
      now = now.add(const Duration(minutes: 2));
      await cache.load('empty', RequestCancellation(), empty);
      expect(calls, 38);
    },
  );
}
