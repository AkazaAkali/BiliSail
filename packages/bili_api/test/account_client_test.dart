import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  for (final balance in <num>[0, 25, 6.25]) {
    test(
      'overview reads B coin balance $balance from the nav wallet',
      () async {
        final transport = _Transport({
          'money': 12.5,
          'wallet': {'bcoin_balance': balance, 'coupon_balance': 5},
        });
        final api = BiliApiClient(transport: transport);
        addTearDown(api.close);
        final result = await AccountClient(api).overview('123');

        expect(result.coins, 12.5);
        expect(result.bCoins, balance);
        expect(result.following, 82);
        expect(transport.paths, [
          '/x/web-interface/nav',
          '/x/web-interface/nav/stat',
        ]);
      },
    );
  }

  for (final (description, nav) in <(String, Map<String, Object?>)>[
    ('missing wallet', {}),
    ('null wallet', {'wallet': null}),
    ('invalid wallet', {'wallet': []}),
    (
      'missing balance',
      {
        'wallet': {'coupon_balance': 5},
      },
    ),
    (
      'null balance',
      {
        'wallet': {'bcoin_balance': null},
      },
    ),
    (
      'invalid balance',
      {
        'wallet': {'bcoin_balance': 'invalid'},
      },
    ),
  ]) {
    test('overview keeps B coins unknown with $description', () async {
      final api = BiliApiClient(transport: _Transport(nav));
      addTearDown(api.close);
      final result = await AccountClient(api).overview('123');

      expect(result.bCoins, isNull);
      expect(result.following, 82);
    });
  }

  test('overview rejects another account before reading statistics', () async {
    final transport = _Transport({
      'mid': 456,
      'wallet': {'bcoin_balance': 25},
    });
    final api = BiliApiClient(transport: transport);
    addTearDown(api.close);

    await expectLater(
      AccountClient(api).overview('123'),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.category,
          'category',
          ApiFailureCategory.authentication,
        ),
      ),
    );
    expect(transport.paths, ['/x/web-interface/nav']);
  });
}

final class _Transport implements ApiTransport {
  _Transport(this.nav);

  final Map<String, Object?> nav;
  final paths = <String>[];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    expect(uri.host, 'api.bilibili.com');
    paths.add(uri.path);
    final data = switch (uri.path) {
      '/x/web-interface/nav' => {'isLogin': true, 'mid': 123, ...nav},
      '/x/web-interface/nav/stat' => {
        'following': 82,
        'follower': 37,
        'dynamic_count': 24,
      },
      _ => throw StateError('unexpected endpoint: ${uri.path}'),
    };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
