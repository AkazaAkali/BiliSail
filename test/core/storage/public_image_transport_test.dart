import 'dart:async';
import 'dart:io';

import 'package:bilisail/core/storage/image_byte_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import 'public_image_test_server.dart';

ImageLoadRequest _limits({
  Duration timeout = const Duration(seconds: 3),
  int bytes = 1024,
}) => ImageLoadRequest(maxBytes: bytes, timeout: timeout);

void main() {
  late PublicImageTestServer server;
  setUp(() async => server = await PublicImageTestServer.start());
  tearDown(() => server.close());

  test(
    'cache-owned pool resets when the account session changes',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final cache = ImageByteCache(
        enabled: false,
        directory: () async => throw StateError('No disk access'),
      );
      addTearDown(cache.close);
      await cache.load(server.uri('/first'));
      await cache.load(server.uri('/second'));
      expect(server.connections, 1);
      await cache.changeScope('user:fixture');
      await cache.load(server.uri('/new-account'));
      expect(server.connections, 2);
      cache.invalidateSession();
      await cache.load(server.uri('/new-epoch'));
      expect(server.connections, 3);
    }, server),
  );

  test(
    'cancelling a pending TLS handshake frees only its borrowed lane',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final stalled = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<Socket>();
      final listener = stalled.listen(accepted.complete);
      addTearDown(() async {
        await listener.cancel();
        await stalled.close();
      });
      final transport = PublicImageTransport(maxConnections: 1);
      addTearDown(transport.close);
      server.connectionPort = stalled.port;
      final cancellation = _limits();
      final result = transport.load(server.uri('/handshake'), cancellation);
      final failure = expectLater(result, throwsA(isA<ImageLoadCancelled>()));
      final socket = await accepted.future;
      addTearDown(socket.destroy);
      cancellation.cancel();
      await failure.timeout(const Duration(seconds: 1));
      server.connectionPort = null;
      expect(await transport.load(server.uri('/good'), _limits()), [1, 2, 3]);
      expect(server.connections, 2);
    }, server),
  );

  test(
    'untrusted TLS certificates are rejected without an accept callback',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final transport = PublicImageTransport();
      addTearDown(transport.close);
      server.trustServer = false;
      await expectLater(
        transport.load(server.uri('/untrusted'), _limits()),
        throwsA(isA<HandshakeException>()),
      );
      expect(server.requests, isEmpty);
    }, server),
  );

  test(
    'same-origin images reuse TLS connection; reset and close release it',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final transport = PublicImageTransport(maxConnections: 2);
      addTearDown(transport.close);
      final firstLimits = _limits();
      await transport.load(server.uri('/first'), firstLimits);
      // Cancelling an already delivered consumer cannot retire the next borrower.
      firstLimits.cancel();
      await transport.load(server.uri('/second'), _limits());
      expect(server.connections, 1);
      expect(server.clients, 1);
      transport.reset();
      await transport.load(server.uri('/third'), _limits());
      expect(server.connections, 2);
      transport.close();
      await expectLater(
        transport.load(server.uri('/closed'), _limits()),
        throwsA(isA<ImageLoadCancelled>()),
      );
    }, server),
  );

  test(
    'one cancelled response does not interrupt another leased connection',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final transport = PublicImageTransport(maxConnections: 2);
      addTearDown(transport.close);
      final started = Completer<void>();
      final slow = Completer<HttpRequest>();
      server.onRequest = (request) {
        if (request.uri.path == '/cancel') {
          request.response.add([1]);
          unawaited(request.response.flush().then((_) => started.complete()));
        } else if (request.uri.path == '/slow') {
          slow.complete(request);
        } else {
          request.response.add([3]);
          unawaited(request.response.close());
        }
      };
      final cancellation = _limits();
      final cancelled = transport.load(server.uri('/cancel'), cancellation);
      final cancelledExpectation = expectLater(
        cancelled,
        throwsA(isA<ImageLoadCancelled>()),
      );
      final other = transport.load(server.uri('/slow'), _limits());
      await started.future;
      final slowRequest = await slow.future;
      await expectLater(
        transport.load(server.uri('/over-capacity'), _limits()),
        throwsA(isA<ImageQueueFull>()),
      );
      cancellation.cancel();
      await cancelledExpectation;
      expect(await transport.load(server.uri('/replacement'), _limits()), [3]);
      slowRequest.response.add([2]);
      await slowRequest.response.close();
      expect(await other, [2]);
      expect(server.connections, 3);
      expect(server.clients, 3);
    }, server),
  );

  test(
    'manual redirects and keep-alive never store cookies or auth',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final transport = PublicImageTransport();
      addTearDown(transport.close);
      server.onRequest = (request) {
        request.response.cookies.add(Cookie('session', 'test-only'));
        if (request.uri.path == '/redirect') {
          request.response.statusCode = 302;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'https://i1.hdslb.com/end',
          );
        } else {
          request.response.add([1]);
        }
        unawaited(request.response.close());
      };
      await transport.load(server.uri('/redirect'), _limits());
      await transport.load(server.uri('/later'), _limits());
      expect(server.requests.length, 3);
      for (final request in server.requests) {
        expect(request.headers.value(HttpHeaders.cookieHeader), isNull);
        expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
        expect(
          request.headers.value(HttpHeaders.refererHeader),
          'https://www.bilibili.com/',
        );
      }
      expect(
        server.clients,
        2,
        reason: 'Cross-origin redirects retire the lease',
      );
    }, server),
  );

  test(
    'invalid redirects, oversize, empty and failed responses retire lanes',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final transport = PublicImageTransport(maxConnections: 1);
      addTearDown(transport.close);
      server.onRequest = (request) {
        switch (request.uri.path) {
          case '/redirect':
            request.response.statusCode = 302;
            request.response.headers.set(
              HttpHeaders.locationHeader,
              'https://example.com/private',
            );
          case '/large':
            request.response.add(List.filled(2048, 1));
          case '/empty':
            break;
          case '/failure':
            request.response.statusCode = 403;
          default:
            request.response.add([1]);
        }
        unawaited(request.response.close());
      };
      for (final path in ['/redirect', '/large', '/empty', '/failure']) {
        await expectLater(
          transport.load(server.uri(path), _limits()),
          throwsA(isA<HttpException>()),
        );
      }
      expect(await transport.load(server.uri('/good'), _limits()), [1]);
      expect(server.connections, 5);
      await expectLater(
        transport.load(Uri.parse('http://i0.hdslb.com/no-tls'), _limits()),
        throwsA(isA<HttpException>()),
      );
      await expectLater(
        transport.load(
          Uri.parse('https://user:password@i0.hdslb.com/image'),
          _limits(),
        ),
        throwsA(isA<HttpException>()),
      );
      expect(server.connections, 5);
    }, server),
  );

  test(
    'deadline cancels headers wait and makes room for the next image',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final transport = PublicImageTransport(maxConnections: 1);
      addTearDown(transport.close);
      server.onRequest = (request) {
        if (request.uri.path != '/stall') {
          request.response.add([1]);
          unawaited(request.response.close());
        }
      };
      await expectLater(
        transport.load(
          server.uri('/stall'),
          _limits(timeout: const Duration(milliseconds: 100)),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(await transport.load(server.uri('/good'), _limits()), [1]);
      expect(server.connections, 2);
    }, server),
  );
}
