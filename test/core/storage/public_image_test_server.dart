import 'dart:async';
import 'dart:io';

/// Local-only TLS fixture. The private key is generated test data and cannot
/// authenticate any public server. Production keeps the platform trust store.
final class PublicImageTestServer extends HttpOverrides {
  PublicImageTestServer._(this.server, this.trust);
  final HttpServer server;
  final SecurityContext trust;
  int clients = 0;
  int connections = 0;
  int? connectionPort;
  bool trustServer = true;
  final requests = <HttpRequest>[];
  void Function(HttpRequest)? onRequest;

  static Future<PublicImageTestServer> start() async {
    const base = 'test/fixtures/public_image_transport';
    final context = SecurityContext()
      ..useCertificateChain('$base/cert.pem')
      ..usePrivateKey('$base/key.pem');
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    final fixture = PublicImageTestServer._(
      server,
      SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('$base/cert.pem'),
    );
    server.listen((request) {
      fixture.requests.add(request);
      final handler = fixture.onRequest;
      if (handler != null) {
        handler(request);
        return;
      }
      request.response.add([1, 2, 3]);
      unawaited(request.response.close());
    });
    return fixture;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    final activeContext =
        context ?? (trustServer ? trust : SecurityContext.defaultContext);
    return super.createHttpClient(activeContext)
      ..findProxy = ((_) => 'DIRECT')
      ..connectionFactory = (uri, proxyHost, proxyPort) async {
        connections++;
        final connection = await Socket.startConnect(
          InternetAddress.loopbackIPv4,
          connectionPort ?? server.port,
        );
        Socket? connected;
        return ConnectionTask.fromSocket(
          connection.socket.then((socket) {
            connected = socket;
            return SecureSocket.secure(
              socket,
              host: uri.host,
              context: activeContext,
            );
          }),
          () {
            connection.cancel();
            connected?.destroy();
          },
        );
      };
  }

  Uri uri(String path, {String host = 'i0.hdslb.com'}) => Uri.https(host, path);
  Future<void> close() async {
    await server.close(force: true);
  }
}
