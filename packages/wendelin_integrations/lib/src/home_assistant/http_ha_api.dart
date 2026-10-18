import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../common/port_exception.dart';
import 'ha_model.dart';
import 'ha_ports.dart';
import 'ha_registry.dart';
import 'ha_url.dart';

/// Home Assistant over its REST API (`/api/…`) and, for room names, the
/// WebSocket API (`/api/websocket`, registries). Endpoint and token come
/// from [HaSecrets] at each call, so a changed setup takes effect at once.
///
/// The token goes only to the saved address: redirects are not followed,
/// and the address passes `HaUrl.parse` again before each call (`http` only
/// for private hosts). No retries (calls change devices).
final class HttpHaApi implements HaApi {
  /// Creates the client; [client] is for tests.
  HttpHaApi(
    this.secrets, {
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  /// Where address and token live.
  final HaSecrets secrets;

  /// Timeout per request.
  final Duration timeout;

  final http.Client _client;

  /// Largest accepted answer.
  static const maxBodyBytes = 8 * 1024 * 1024;

  Future<HaEndpoint> _endpoint() async {
    final e = await secrets.endpoint();
    if (e == null) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Home Assistant ist nicht eingerichtet.',
      );
    }
    // Defence in depth: a stored address from an older version or a changed
    // rule must not send the token over plain http to a public host.
    try {
      return HaEndpoint(url: HaUrl.parse(e.url), token: e.token);
    } on PortException {
      throw const PortException(
        PortErrorKind.failed,
        'Die gespeicherte Home-Assistant-Adresse ist nicht erlaubt.',
      );
    }
  }

  Future<Object?> _json(String method, String path, {Object? body}) async {
    final e = await _endpoint();
    final request = http.Request(method, Uri.parse('${e.url}$path'))
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer ${e.token}'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.StreamedResponse response;
    final List<int> bytes;
    try {
      response = await _client.send(request).timeout(timeout);
      bytes = await _read(response).timeout(timeout);
    } on TimeoutException {
      throw const PortException(
        PortErrorKind.unavailable,
        'Home Assistant antwortet nicht (Zeitüberschreitung).',
      );
    } on _TooBig {
      throw const PortException(
        PortErrorKind.failed,
        'Unerwartete Antwort von Home Assistant (zu groß).',
      );
    } on Object catch (e) {
      if (e is PortException) rethrow;
      throw const PortException(
        PortErrorKind.unavailable,
        'Home Assistant ist nicht erreichbar.',
      );
    }
    final code = response.statusCode;
    if (code >= 300 && code < 400) {
      throw const PortException(
        PortErrorKind.failed,
        'Home Assistant leitet weiter; die Adresse stimmt nicht '
        '(Weiterleitungen werden nicht gefolgt).',
      );
    }
    if (code == 401 || code == 403) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Home Assistant hat das Token abgelehnt.',
      );
    }
    if (code == 404) {
      throw const PortException(
        PortErrorKind.notFound,
        'Nicht gefunden in Home Assistant.',
      );
    }
    if (code >= 500) {
      throw const PortException(
        PortErrorKind.unavailable,
        'Home Assistant meldet einen Serverfehler.',
      );
    }
    if (code < 200 || code >= 300) {
      throw PortException(
        PortErrorKind.failed,
        'Unerwartete Antwort von Home Assistant (HTTP $code).',
      );
    }
    if (bytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const PortException(
        PortErrorKind.failed,
        'Unerwartete Antwort von Home Assistant (kein JSON); stimmt die '
        'Adresse?',
      );
    }
  }

  Future<List<int>> _read(http.StreamedResponse r) async {
    final out = <int>[];
    await for (final chunk in r.stream) {
      out.addAll(chunk);
      if (out.length > maxBodyBytes) throw _TooBig();
    }
    return out;
  }

  @override
  Future<String> check() async {
    final json = await _json('GET', '/api/config');
    return json is Map<String, Object?> && json['version'] is String
        ? json['version']! as String
        : '';
  }

  @override
  Future<List<HaState>> states() async {
    final json = await _json('GET', '/api/states');
    if (json is! List<Object?>) throw _unexpected();
    return [for (final j in json) ?HaState.fromJson(j)];
  }

  @override
  Future<HaState> state(String entityId) async {
    final json = await _json(
      'GET',
      '/api/states/${Uri.encodeComponent(entityId)}',
    );
    return HaState.fromJson(json) ?? (throw _unexpected());
  }

  @override
  Future<void> callService(HaCall call) async {
    await _json(
      'POST',
      '/api/services/${Uri.encodeComponent(call.domain)}/'
          '${Uri.encodeComponent(call.service)}',
      body: call.data,
    );
  }

  @override
  Future<List<HaEntity>> entities() async {
    final all = await states();
    final areas = await _areasByEntity();
    return haEntitiesFrom(all, areas);
  }

  /// Rooms per entity from the WebSocket registries; empty when the user
  /// is no admin or the WebSocket fails (names then come without rooms).
  Future<Map<String, String>> _areasByEntity() async {
    final e = await _endpoint();
    WebSocket? socket;
    try {
      socket = await _openSocket(Uri.parse('${e.url}/api/websocket'));
      return await haFetchAreas(socket, socket.add, e.token).timeout(timeout);
    } on Object {
      return const {};
    } finally {
      unawaited(
        socket?.close().catchError((Object _) {}) ?? Future<void>.value(),
      );
    }
  }

  /// Opens the WebSocket by hand: `WebSocket.connect` follows redirects,
  /// which would send the token to a foreign host. Only a direct `101`
  /// answer from the saved address counts.
  Future<WebSocket> _openSocket(Uri url) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl('GET', url).timeout(timeout);
      request.followRedirects = false;
      final key = base64.encode(
        List<int>.generate(16, (_) => Random.secure().nextInt(256)),
      );
      request.headers
        ..set(HttpHeaders.connectionHeader, 'Upgrade')
        ..set(HttpHeaders.upgradeHeader, 'websocket')
        ..set('Sec-WebSocket-Key', key)
        ..set('Sec-WebSocket-Version', '13');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.switchingProtocols) {
        await response.drain<void>().catchError((Object _) {});
        throw const PortException(
          PortErrorKind.failed,
          'Home Assistant hat die WebSocket-Verbindung nicht angenommen.',
        );
      }
      final upgrade = response.headers.value(HttpHeaders.upgradeHeader);
      if (upgrade == null ||
          upgrade.toLowerCase() != 'websocket' ||
          response.headers.value('Sec-WebSocket-Accept') != _acceptFor(key)) {
        await response.detachSocket().then((s) => s.destroy());
        throw const PortException(
          PortErrorKind.failed,
          'Home Assistant hat die WebSocket-Verbindung nicht angenommen.',
        );
      }
      // The caller closes the returned WebSocket.
      // ignore: close_sinks
      final socket = await response.detachSocket();
      return WebSocket.fromUpgradedSocket(socket, serverSide: false);
    } finally {
      client.close();
    }
  }

  /// `Sec-WebSocket-Accept` the server must answer to [key] (RFC 6455).
  static String _acceptFor(String key) => base64.encode(
    _sha1(utf8.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11')),
  );

  static List<int> _sha1(List<int> data) {
    int rotl(int x, int n) => ((x << n) | (x >> (32 - n))) & 0xffffffff;
    final bytes = [...data, 0x80];
    while (bytes.length % 64 != 56) {
      bytes.add(0);
    }
    final bits = data.length * 8;
    for (var i = 7; i >= 0; i--) {
      bytes.add((bits >> (i * 8)) & 0xff);
    }
    var h0 = 0x67452301;
    var h1 = 0xEFCDAB89;
    var h2 = 0x98BADCFE;
    var h3 = 0x10325476;
    var h4 = 0xC3D2E1F0;
    for (var c = 0; c < bytes.length; c += 64) {
      final w = List<int>.filled(80, 0);
      for (var i = 0; i < 16; i++) {
        w[i] =
            (bytes[c + i * 4] << 24) |
            (bytes[c + i * 4 + 1] << 16) |
            (bytes[c + i * 4 + 2] << 8) |
            bytes[c + i * 4 + 3];
      }
      for (var i = 16; i < 80; i++) {
        w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
      }
      var a = h0, b = h1, cc = h2, d = h3, e = h4;
      for (var i = 0; i < 80; i++) {
        final int f, k;
        if (i < 20) {
          f = (b & cc) | ((~b & 0xffffffff) & d);
          k = 0x5A827999;
        } else if (i < 40) {
          f = b ^ cc ^ d;
          k = 0x6ED9EBA1;
        } else if (i < 60) {
          f = (b & cc) | (b & d) | (cc & d);
          k = 0x8F1BBCDC;
        } else {
          f = b ^ cc ^ d;
          k = 0xCA62C1D6;
        }
        final t = (rotl(a, 5) + f + e + k + w[i]) & 0xffffffff;
        e = d;
        d = cc;
        cc = rotl(b, 30);
        b = a;
        a = t;
      }
      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + cc) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
    }
    return [
      for (final h in [h0, h1, h2, h3, h4])
        for (var i = 3; i >= 0; i--) (h >> (i * 8)) & 0xff,
    ];
  }

  PortException _unexpected() => const PortException(
    PortErrorKind.failed,
    'Unerwartete Antwort von Home Assistant.',
  );

  /// Releases the HTTP client.
  void close() => _client.close();
}

class _TooBig implements Exception {}
