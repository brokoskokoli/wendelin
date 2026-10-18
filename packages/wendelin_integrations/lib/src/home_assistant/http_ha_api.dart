import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    final url = Uri.parse('${e.url.replaceFirst('http', 'ws')}/api/websocket');
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(url.toString()).timeout(timeout);
      return await haFetchAreas(socket, socket.add, e.token).timeout(timeout);
    } on Object {
      return const {};
    } finally {
      unawaited(
        socket?.close().catchError((Object _) {}) ?? Future<void>.value(),
      );
    }
  }

  PortException _unexpected() => const PortException(
    PortErrorKind.failed,
    'Unerwartete Antwort von Home Assistant.',
  );

  /// Releases the HTTP client.
  void close() => _client.close();
}

class _TooBig implements Exception {}
