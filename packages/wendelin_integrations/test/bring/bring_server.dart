import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Content of `test/fixtures/bring/<name>`.
String bringFixture(String name) =>
    File('test/fixtures/bring/$name').readAsStringSync();

/// A canned answer that replaces the emulated one.
typedef Canned = ({int status, String body, Map<String, String> headers});

/// Canned answer helper.
Canned canned(
  int status, [
  String body = '',
  Map<String, String> headers = const {},
]) => (status: status, body: body, headers: headers);

/// Emulates the Bring! REST API behind a [MockClient], seeded from the
/// fixtures (answers have the fixture shape). Records all requests;
/// [next] answers the next requests with canned responses instead.
final class BringServer {
  /// Creates the server in the contract state.
  BringServer() {
    for (final l in (_json('lists.json')['lists']! as List<Object?>)) {
      final m = l! as Map<String, Object?>;
      _lists.add((uuid: m['listUuid']! as String, name: m['name']! as String));
    }
    _items[_zuhause] = _readItems('items_zuhause.json');
    _items[_buero] = _readItems('items_buero.json');
  }

  static const _zuhause = '00000000-0000-4000-8000-0000000000a1';
  static const _buero = '00000000-0000-4000-8000-0000000000a2';
  static const _user = '00000000-0000-4000-8000-000000000001';

  /// Accepted login.
  String email = 'kontrakt@example.org', password = 'kanarien-passwort';

  final _lists = <({String uuid, String name})>[];
  final _items = <String, Map<String, List<Map<String, Object?>>>>{};
  final _access = <String>{};
  final _refresh = <String>{};
  var _n = 0;

  /// All requests in order.
  final List<http.Request> requests = [];

  /// Canned answers for the next requests (first = next).
  final List<Canned> next = [];

  /// Whether the refresh answer omits `refresh_token`.
  bool refreshWithoutNewToken = false;

  /// While `true`, every access token is rejected (also fresh ones).
  bool rejectTokens = false;

  /// Invalidates all access tokens.
  void expireTokens() => _access.clear();

  /// Invalidates all refresh tokens.
  void revokeRefresh() => _refresh.clear();

  /// The mock HTTP client.
  late final http.Client client = MockClient(_handle);

  /// An [HttpBringApi] on this server.
  HttpBringApi api({
    void Function(String)? log,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpBringApi(client: client, log: log, timeout: timeout);

  /// Open item names of the list „Zuhause“.
  List<String> openAtHome() => [
    for (final i in _items[_zuhause]!['purchase']!) i['itemId']! as String,
  ];

  static Map<String, Object?> _json(String name) =>
      jsonDecode(bringFixture(name)) as Map<String, Object?>;

  static Map<String, List<Map<String, Object?>>> _readItems(String name) {
    final items = _json(name)['items']! as Map<String, Object?>;
    return {
      for (final key in ['purchase', 'recently'])
        key: [
          for (final e in items[key]! as List<Object?>)
            Map<String, Object?>.of(e! as Map<String, Object?>),
        ],
    };
  }

  http.Response _respond(int status, [Object? body]) => http.Response.bytes(
    body == null ? const [] : utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=UTF-8'},
  );

  http.Response get _unauthorized =>
      http.Response.bytes(utf8.encode(bringFixture('unauthorized.json')), 401);

  Map<String, Object?> _issue(String fixture) {
    final m = _json(fixture);
    _n++;
    final a = 'fixture-access-x$_n';
    final r = 'fixture-refresh-x$_n';
    _access.add(a);
    _refresh.add(r);
    m['access_token'] = a;
    if (refreshWithoutNewToken && fixture == 'token.json') {
      m.remove('refresh_token');
    } else {
      m['refresh_token'] = r;
    }
    return m;
  }

  Future<http.Response> _handle(http.Request req) async {
    requests.add(req);
    if (next.isNotEmpty) {
      final c = next.removeAt(0);
      return http.Response.bytes(
        utf8.encode(c.body),
        c.status,
        headers: c.headers,
      );
    }
    if (req.headers['X-BRING-API-KEY'] != bringPublicApiKey) {
      return _respond(403, {'error': 'Forbidden'});
    }
    final path = req.url.pathSegments.where((s) => s.isNotEmpty).toList();
    final p = path.join('/');
    if (req.method == 'POST' && p == 'rest/v2/bringauth') {
      final f = req.bodyFields;
      if (f['email'] != email || f['password'] != password) {
        return _unauthorized;
      }
      return _respond(200, _issue('login.json'));
    }
    if (req.method == 'POST' && p == 'rest/v2/bringauth/token') {
      final f = req.bodyFields;
      if (f['grant_type'] != 'refresh_token' ||
          !_refresh.remove(f['refresh_token'])) {
        return _unauthorized;
      }
      return _respond(200, _issue('token.json'));
    }
    final auth = req.headers['Authorization'] ?? '';
    if (rejectTokens ||
        !auth.startsWith('Bearer ') ||
        !_access.contains(auth.substring(7))) {
      return _unauthorized;
    }
    if (req.method == 'GET' && p == 'rest/bringusers/$_user/lists') {
      return _respond(200, {
        'lists': [
          for (final l in _lists)
            {'listUuid': l.uuid, 'name': l.name, 'theme': 'x'},
        ],
      });
    }
    if (path.length >= 4 &&
        path.sublist(0, 3).join('/') == 'rest/v2/bringlists') {
      final items = _items[path[3]];
      if (items == null) return _respond(404, {'error': 'Not Found'});
      if (req.method == 'GET' && path.length == 4) {
        return _respond(200, {
          'uuid': path[3],
          'status': 'SHARED',
          'items': items,
        });
      }
      if (req.method == 'PUT' && path.length == 5 && path[4] == 'items') {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        for (final c in body['changes']! as List<Object?>) {
          _apply(items, c! as Map<String, Object?>);
        }
        return _respond(204);
      }
    }
    return _respond(404, {'error': 'Not Found'});
  }

  void _apply(
    Map<String, List<Map<String, Object?>>> items,
    Map<String, Object?> c,
  ) {
    final name = c['itemId']! as String;
    final spec = c['spec']! as String;
    final purchase = items['purchase']!;
    final recently = items['recently']!;
    Map<String, Object?>? take(List<Map<String, Object?>> l) {
      final i = l.indexWhere((e) => e['itemId'] == name);
      return i < 0 ? null : l.removeAt(i);
    }

    switch (c['operation']) {
      case 'TO_PURCHASE':
        final old = take(purchase) ?? take(recently);
        purchase.add({
          'uuid': old?['uuid'] ?? 'neu-${++_n}',
          'itemId': name,
          'specification': spec,
          'attributes': <Object?>[],
        });
      case 'TO_RECENTLY':
        final old = take(purchase);
        if (old == null) return;
        take(recently);
        recently.insert(0, {...old, 'specification': spec});
      case 'REMOVE':
        take(purchase);
        take(recently);
    }
  }
}
