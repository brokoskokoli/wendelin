@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

/// Local TLS server with a throw-away certificate (made with `openssl`);
/// it records which connection carried which request.
final class _Server {
  _Server._(this.socket, this.der);

  final SecureServerSocket socket;
  final Uint8List der;

  /// Remote ports of connections on which an HTTP request arrived.
  final List<int> requestPorts = [];

  /// Bytes received after the handshake, over all connections.
  int bytes = 0;

  static Future<_Server?> start(Directory dir) async {
    final key = '${dir.path}/k.pem', crt = '${dir.path}/c.pem';
    final r = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'ec',
      '-pkeyopt',
      'ec_paramgen_curve:prime256v1',
      '-nodes',
      '-keyout',
      key,
      '-out',
      crt,
      '-days',
      '2',
      '-subj',
      '/CN=localhost',
      '-addext',
      'subjectAltName=DNS:localhost,IP:127.0.0.1',
    ]);
    if (r.exitCode != 0) return null;
    final context = SecurityContext()
      ..useCertificateChain(crt)
      ..usePrivateKey(key);
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    final der =
        (await Process.run('openssl', [
              'x509',
              '-in',
              crt,
              '-outform',
              'DER',
            ], stdoutEncoding: null)).stdout
            as List<int>;
    final s = _Server._(server, Uint8List.fromList(der));
    server.listen((client) {
      client.listen(
        (data) {
          s.bytes += data.length;
          s.requestPorts.add(client.remotePort);
          client.add(
            utf8.encode('HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nok'),
          );
          // Keep-alive: the connection stays open for the next request.
        },
        onError: (_) {},
        onDone: () => client.destroy(),
      );
    });
    return s;
  }

  /// Connects to this server and records the sockets.
  TlsConnect connectRecording(List<int> sockets) {
    return (url) async {
      // The throw-away certificate is not a trust anchor; the pin decides.
      final task = await SecureSocket.startConnect(
        'localhost',
        socket.port,
        onBadCertificate: (_) => true,
      );
      return ConnectionTask.fromSocket(
        task.socket.then((s) {
          sockets.add(s.port);
          return s;
        }),
        task.cancel,
      );
    };
  }
}

String _pinOf(Uint8List der) => FakeAttestationCrypto()
    .spkiSha256(der)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

void main() {
  late Directory dir;
  _Server? server;
  late TlsPinGate gate;
  final sockets = <int>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wendelin_tls');
    server = await _Server.start(dir);
    gate = TlsPinGate(spkiSha256: FakeAttestationCrypto().spkiSha256);
    sockets.clear();
  });

  tearDown(() async {
    await server?.socket.close();
    await dir.delete(recursive: true);
  });

  PinnedHttpClient client({bool enforce = true}) => PinnedHttpClient(
    gate: gate,
    enforce: enforce,
    connect: server!.connectRecording(sockets),
  );

  Uri url() => Uri.parse('https://localhost:${server!.socket.port}/v1/chat');
  Future<http.Response> post(http.Client c) =>
      c.post(url(), body: 'GEHEIMER-BODY');

  group('PinnedHttpClient (echte TLS-Verbindung)', () {
    test(
      'passender Pin: Anfrage geht über genau die geprüfte Verbindung',
      () async {
        if (server == null) return markTestSkipped('openssl fehlt');
        gate.expect(_pinOf(server!.der));
        final c = client();
        final response = await post(c);
        expect(response.body, 'ok');
        expect(sockets, hasLength(1));
        // The request arrived on the socket whose certificate was checked.
        expect(server!.requestPorts, [sockets.single]);
        c.close();
      },
    );

    test('falscher Pin: Fehler, kein Byte des Bodys gesendet', () async {
      if (server == null) return markTestSkipped('openssl fehlt');
      gate.expect('ab' * 32);
      final c = client();
      await expectLater(post(c), throwsA(isA<AttestationFailedException>()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server!.bytes, 0);
      c.close();
    });

    test('kein Pin aus der Attestierung: Fehler, nichts gesendet', () async {
      if (server == null) return markTestSkipped('openssl fehlt');
      final c = client();
      await expectLater(post(c), throwsA(isA<AttestationFailedException>()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server!.bytes, 0);
      c.close();
    });

    test(
      'Pinwechsel: gleiche Verbindung bei gleichem Pin, danach neu geprüft',
      () async {
        if (server == null) return markTestSkipped('openssl fehlt');
        final pin = _pinOf(server!.der);
        gate.expect(pin);
        final c = client();
        await post(c);
        await post(c);
        // Same pin: the kept-alive connection is reused.
        expect(sockets, hasLength(1));
        gate.expect('cd' * 32);
        await expectLater(post(c), throwsA(isA<AttestationFailedException>()));
        gate.expect(pin);
        expect((await post(c)).body, 'ok');
        // Not the old connection: a new one was opened and checked.
        expect(sockets, hasLength(3));
        c.close();
      },
    );

    test(
      'Messmodus: misst, blockiert nie, neue Verbindung je Anfrage',
      () async {
        if (server == null) return markTestSkipped('openssl fehlt');
        final c = client(enforce: false);
        expect((await post(c)).statusCode, 200);
        expect(gate.observed, _pinOf(server!.der));
        await post(c);
        expect(sockets, hasLength(2));
        c.close();
      },
    );

    test('http-URL wird abgelehnt', () async {
      final c = PinnedHttpClient(gate: gate, enforce: true);
      await expectLater(
        c.get(Uri.parse('http://localhost:1/')),
        throwsA(isA<SocketException>()),
      );
      c.close();
    });
  });

  group('TlsPinGate', () {
    test('Zustände', () {
      final g = TlsPinGate(
        spkiSha256: (der) => Uint8List.fromList(List.filled(32, der.first)),
      );
      expect(
        () => g.enforce(Uint8List.fromList([1])),
        throwsA(isA<AttestationFailedException>()),
      );
      g.expect('01' * 32);
      expect(g.generation, 1);
      g.expect('01' * 32);
      expect(g.generation, 1);
      g.enforce(Uint8List.fromList([1]));
      expect(() => g.enforce(null), throwsA(isA<AttestationFailedException>()));
      expect(
        () => g.enforce(Uint8List(0)),
        throwsA(isA<AttestationFailedException>()),
      );
      expect(
        () => g.enforce(Uint8List.fromList([2])),
        throwsA(isA<AttestationFailedException>()),
      );
      g.observe(Uint8List.fromList([2]));
      expect(g.observed, '02' * 32);
      g.resetObserved();
      expect(g.observed, isNull);
    });
  });
}
