import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:http/io_client.dart';

import 'tls_pin_gate.dart';

/// Opens the TLS connection to [url]; replaceable in tests (own trust
/// anchor, recording).
typedef TlsConnect = Future<ConnectionTask<SecureSocket>> Function(Uri url);

Future<ConnectionTask<SecureSocket>> _systemConnect(Uri url) =>
    SecureSocket.startConnect(url.host, url.hasPort ? url.port : 443);

/// HTTP client whose TLS connections are measured against [gate] on the
/// connection the request uses (WP61).
///
/// - [enforce] `true`: a connection is only handed to the request after
///   its certificate matches `gate.expected`; otherwise the connection is
///   destroyed and `send` throws `AttestationFailedException`. Used for
///   everything that carries user content.
/// - [enforce] `false`: only measures (`gate.observed`) and never reuses a
///   connection, so every request is measured freshly. Used for the
///   attestation endpoints.
///
/// Proxies and plain `http:` URLs are refused (fail-closed).
final class PinnedHttpClient extends http.BaseClient {
  /// Creates the client.
  PinnedHttpClient({
    required this.gate,
    required this.enforce,
    TlsConnect? connect,
    this.idleTimeout = const Duration(minutes: 5),
  }) : connect = connect ?? _systemConnect {
    _fresh();
  }

  /// Pin state shared with the verifier.
  final TlsPinGate gate;

  /// Whether a mismatch stops the request.
  final bool enforce;

  /// Opens the TLS connection.
  final TlsConnect connect;

  /// How long an idle connection of the enforcing client stays open (the
  /// Dart default of 15 s costs a new handshake and pin check after every
  /// short pause). The pin is judged once per connection, as before.
  final Duration idleTimeout;
  late HttpClient _http;

  /// The current platform client (tests: idle timeout).
  @visibleForTesting
  HttpClient get debugHttpClient => _http;
  late IOClient _io;
  late int _generation;

  void _fresh() {
    _generation = gate.generation;
    _http = HttpClient()
      ..idleTimeout = enforce ? idleTimeout : const Duration(seconds: 15)
      ..findProxy = ((_) => 'DIRECT')
      ..connectionFactory = _factory;
    _io = IOClient(_http);
  }

  Future<ConnectionTask<Socket>> _factory(
    Uri url,
    String? proxyHost,
    int? proxyPort,
  ) async {
    if (url.scheme != 'https' || proxyHost != null) {
      throw const SocketException(
        'TLS-Pinning braucht eine direkte https-Verbindung',
      );
    }
    final task = await connect(url);
    final checked = task.socket.then<Socket>((socket) {
      try {
        if (enforce) {
          gate.enforce(socket.peerCertificate?.der);
        } else {
          gate.observe(socket.peerCertificate?.der);
        }
      } on Object {
        socket.destroy();
        rethrow;
      }
      return socket;
    });
    return ConnectionTask.fromSocket(checked, task.cancel);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (enforce && gate.generation != _generation) {
      _http.close(); // idle connections of the old pin; in-flight ones finish
      _fresh();
    }
    if (!enforce) {
      gate.resetObserved();
      request.headers['connection'] = 'close';
    }
    return _io.send(request);
  }

  @override
  void close() => _io.close();
}
