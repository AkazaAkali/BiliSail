import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../api_client.dart';
import '../models.dart';

final class ApiHighEnergyPoint {
  const ApiHighEnergyPoint(this.fraction, this.intensity);
  final double fraction, intensity;
}

/// Bounded, normalized relative intensity; it is not an exact comment count.
final class ApiHighEnergyTrend {
  ApiHighEnergyTrend({
    required this.step,
    required this.span,
    required List<ApiHighEnergyPoint> points,
  }) : points = List.unmodifiable(points);
  final Duration step, span;
  final List<ApiHighEnergyPoint> points;
}

final class HighEnergyClient {
  const HighEnergyClient(this.api);
  final BiliApiClient api;

  Future<ApiHighEnergyTrend?> load(
    String aid,
    String cid,
    String bvid, {
    ApiRequestContext? context,
  }) async {
    final bytes = await api.highEnergyBytes(aid, cid, bvid, context: context);
    // Decode and reduce together: no large JSON graph comes back to the UI.
    final result = bytes.length > 32 * 1024
        ? await _decodeLarge(bytes)
        : _decode(bytes);
    if (context?.cancellation?.isCancelled == true) {
      throw const ApiFailure(ApiFailureCategory.cancelled, 'high_energy');
    }
    return result;
  }
}

// Create the isolate closure outside the client method so it cannot capture
// transport/session objects that are not sendable across isolates.
Future<ApiHighEnergyTrend?> _decodeLarge(Uint8List bytes) =>
    Isolate.run(() => _decode(bytes));

ApiHighEnergyTrend? _decode(Uint8List bytes) {
  const failure = ApiFailure(ApiFailureCategory.protocol, 'high_energy');
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw failure;
  }
  if (decoded is! Map<String, Object?>) throw failure;
  final modules = decoded['modules'];
  if (modules is! List || modules.length > 16) throw failure;
  for (final module in modules) {
    if (module is! Map<String, Object?>) throw failure;
    if (module['name'] != 'pbp') continue;
    final params = module['params'];
    if (params is! Map<String, Object?>) throw failure;
    final data = params['data'];
    if (data is! Map<String, Object?>) throw failure;
    final tags = data['tagstr'];
    if (tags != null && (tags is! String || tags.length > 4096)) throw failure;
    if (tags is String && tags.split('&').contains('pbphide_1')) return null;
    final events = data['events'];
    if (events is! Map<String, Object?>) throw failure;
    final values = events['default'];
    final step = data['step_sec'];
    if (values is! List ||
        values.length > 20000 ||
        step is! num ||
        !step.isFinite ||
        step <= 0) {
      throw failure;
    }
    if (values.isEmpty) return null;
    final stepMs = step.toDouble() * 1000;
    final spanMs = stepMs * values.length;
    if (stepMs < 1 ||
        !spanMs.isFinite ||
        spanMs > const Duration(days: 7).inMilliseconds) {
      throw failure;
    }
    var peak = 0.0;
    for (final value in values) {
      if (value is! num || !value.isFinite || value < 0) throw failure;
      peak = math.max(peak, value.toDouble());
    }
    if (peak == 0 || values.length < 2) return null;
    final indices = <int>[0];
    // 255 ordered min/max buckets plus the two endpoints: at most 512 points.
    if (values.length <= 512) {
      indices.addAll(List.generate(values.length - 2, (i) => i + 1));
    } else {
      for (var bucket = 0; bucket < 255; bucket++) {
        final start = 1 + (values.length - 2) * bucket ~/ 255;
        final end = 1 + (values.length - 2) * (bucket + 1) ~/ 255;
        var minIndex = start, maxIndex = start;
        for (var i = start + 1; i < end; i++) {
          if ((values[i] as num) < (values[minIndex] as num)) minIndex = i;
          if ((values[i] as num) > (values[maxIndex] as num)) maxIndex = i;
        }
        indices.add(math.min(minIndex, maxIndex));
        if (minIndex != maxIndex) indices.add(math.max(minIndex, maxIndex));
      }
    }
    indices.add(values.length - 1);
    return ApiHighEnergyTrend(
      step: Duration(milliseconds: stepMs.round()),
      span: Duration(milliseconds: spanMs.round()),
      points: [
        for (final i in indices)
          ApiHighEnergyPoint(
            i / (values.length - 1),
            (values[i] as num).toDouble() / peak,
          ),
      ],
    );
  }
  return null;
}
