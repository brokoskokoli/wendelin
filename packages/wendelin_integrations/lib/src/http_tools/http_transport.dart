import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'http_target.dart';

/// Read access to the secrets referenced by HTTP-tool auth methods.
///
/// The app implements it on top of its `SecretStore`. Secrets are read only
/// right before a request is sent and are never part of results, error
/// texts, audit arguments or confirmation texts.
abstract interface class HttpToolSecrets {
  /// The secret stored under [secretRef], or `null` if there is none.
  Future<String?> read(String secretRef);
}

/// Sends one request of an HTTP tool to a checked [HttpTarget].
abstract interface class HttpToolTransport {
  /// Sends [request] (redirects are not followed) to [target].
  Future<http.StreamedResponse> send(
    http.BaseRequest request,
    HttpTarget target,
  );
}

/// Transport over any [http.Client] (tests with `MockClient`). Does **not**
/// pin the checked addresses: the client resolves the host again. Use
/// [PinnedHttpToolTransport] in the app.
final class ClientHttpToolTransport implements HttpToolTransport {
  /// Creates the transport.
  ClientHttpToolTransport(this.client);

  /// The underlying client.
  final http.Client client;

  @override
  Future<http.StreamedResponse> send(
    http.BaseRequest request,
    HttpTarget target,
  ) => client.send(request);
}

/// Transport over `dart:io` that connects only to the addresses checked by
/// `checkHttpTarget` (DNS pinning): the host name is not resolved a second
/// time, so a rebinding DNS answer cannot redirect the connection. TLS
/// still verifies the certificate against the host name (SNI). No proxy.
final class PinnedHttpToolTransport implements HttpToolTransport {
  /// Creates the transport; [context] for custom TLS trust (tests).
  PinnedHttpToolTransport({
    this.context,
    this.connectTimeout = const Duration(seconds: 10),
  });

  /// TLS context (default: system trust).
  final SecurityContext? context;

  /// Time limit for establishing the TCP connection.
  final Duration connectTimeout;

  @override
  Future<http.StreamedResponse> send(
    http.BaseRequest request,
    HttpTarget target,
  ) async {
    final io = HttpClient(context: context)
      ..findProxy = ((_) => 'DIRECT')
      ..connectionFactory = (uri, proxyHost, proxyPort) {
        if (!target.sameOrigin(uri)) {
          return Future.error(
            const SocketException('Ziel weicht vom geprüften Origin ab'),
          );
        }
        return Future.value(
          ConnectionTask.fromSocket(_connect(uri, target), () {}),
        );
      };
    final client = IOClient(io);
    try {
      return await client.send(request);
    } finally {
      // Hält die Verbindung offen, bis die Antwort gelesen ist.
      io.close();
    }
  }

  Future<Socket> _connect(Uri uri, HttpTarget target) async {
    Object? lastError;
    for (final address in target.addresses) {
      try {
        final socket = await Socket.connect(
          address,
          uri.port,
          timeout: connectTimeout,
        );
        if (!uri.isScheme('https')) return socket;
        return await SecureSocket.secure(
          socket,
          host: uri.host,
          context: context,
        );
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? const SocketException('keine Adresse');
  }
}
