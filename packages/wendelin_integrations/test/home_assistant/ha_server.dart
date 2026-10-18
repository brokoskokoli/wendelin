import 'dart:convert';
import 'dart:io';

import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Home Assistant rebuilt as a local server for `HttpHaApi`: REST under
/// `/api/…` and the WebSocket `/api/websocket` with the registries, backed
/// by a [FakeHaApi]. Only the token [token] is accepted.
final class HaTestServer {
  HaTestServer._(this._server, this.fake, this.token);

  /// Starts a server on a free loopback port.
  static Future<HaTestServer> start({String token = 'kanarien-token'}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final s = HaTestServer._(server, FakeHaApi(), token);
    server.listen(s._handle);
    return s;
  }

  final HttpServer _server;

  /// The state behind the server.
  final FakeHaApi fake;

  /// The accepted token.
  final String token;

  /// Headers of every request in order (lower-case keys).
  final List<Map<String, String>> seen = [];

  /// Paths of every request in order.
  final List<String> paths = [];

  /// Next answers: status codes returned instead of handling (FIFO).
  final List<int> failWith = [];

  /// Body returned for the next REST call instead of JSON (e.g. HTML).
  String? rawBody;

  /// Registry answer mode: `false` makes registry calls fail (non-admin).
  bool registriesAllowed = true;

  /// Address for the app.
  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest r) async {
    paths.add('${r.method} ${r.uri.path}');
    if (r.uri.path == '/api/websocket') {
      await _socket(await WebSocketTransformer.upgrade(r));
      return;
    }
    seen.add({
      for (final MapEntry(:key, :value) in _headers(r).entries) key: value,
    });
    final res = r.response;
    if (failWith.isNotEmpty) {
      res.statusCode = failWith.removeAt(0);
      if (res.statusCode >= 300 && res.statusCode < 400) {
        res.headers.set('location', 'http://127.0.0.1:1/elsewhere');
      }
      await res.close();
      return;
    }
    if (r.headers.value('authorization') != 'Bearer $token') {
      res.statusCode = 401;
      await res.close();
      return;
    }
    if (rawBody != null) {
      res.headers.contentType = ContentType.html;
      res.write(rawBody);
      rawBody = null;
      await res.close();
      return;
    }
    final path = r.uri.path;
    try {
      Object? out;
      if (path == '/api/config') {
        out = {'version': fake.version};
      } else if (path == '/api/states') {
        out = [for (final s in await fake.states()) _json(s)];
      } else if (path.startsWith('/api/states/')) {
        out = _json(await fake.state(Uri.decodeComponent(path.substring(12))));
      } else if (path.startsWith('/api/services/') && r.method == 'POST') {
        final parts = path.substring(14).split('/');
        final body = jsonDecode(
          await utf8.decoder.bind(r).join(),
        ) as Map<String, Object?>;
        await fake.callService((
          domain: parts[0],
          service: parts[1],
          data: body,
        ));
        out = <Object?>[];
      } else {
        res.statusCode = 404;
        await res.close();
        return;
      }
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(out));
    } on Object {
      res.statusCode = 404;
    }
    await res.close();
  }

  Map<String, String> _headers(HttpRequest r) {
    final out = <String, String>{};
    r.headers.forEach((n, v) => out[n] = v.join(','));
    return out;
  }

  Map<String, Object?> _json(HaState s) => {
    'entity_id': s.entityId,
    'state': s.state,
    'attributes': s.attributes,
  };

  Future<void> _socket(WebSocket ws) async {
    ws.add(jsonEncode({'type': 'auth_required'}));
    await for (final raw in ws) {
      final m = jsonDecode(raw as String) as Map<String, Object?>;
      if (m['type'] == 'auth') {
        ws.add(
          jsonEncode({
            'type': m['access_token'] == token ? 'auth_ok' : 'auth_invalid',
          }),
        );
        continue;
      }
      final id = m['id'];
      if (!registriesAllowed) {
        ws.add(
          jsonEncode({
            'id': id,
            'type': 'result',
            'success': false,
            'error': {'code': 'unauthorized'},
          }),
        );
        continue;
      }
      final result = switch (m['type']) {
        'config/area_registry/list' => [
          for (final a in fake.areas.values.toSet())
            {'area_id': a.toLowerCase(), 'name': a},
        ],
        'config/device_registry/list' => <Object?>[],
        'config/entity_registry/list' => [
          for (final e in fake.areas.entries)
            {'entity_id': e.key, 'area_id': e.value.toLowerCase()},
        ],
        _ => <Object?>[],
      };
      ws.add(
        jsonEncode({
          'id': id,
          'type': 'result',
          'success': true,
          'result': result,
        }),
      );
    }
  }
}
