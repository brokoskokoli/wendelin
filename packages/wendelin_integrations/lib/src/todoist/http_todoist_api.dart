import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import '../common/time.dart';
import 'todoist_api.dart';

/// Default base URL of the Todoist API v1.
final todoistApiBaseUrl = Uri.parse('https://api.todoist.com/api/v1/');

/// [TodoistApi] over HTTPS against the Todoist API v1 (the REST API v2 is
/// retired). Lists are cursor-paginated (`next_cursor`). No request is
/// repeated automatically. After HTTP 429 every call fails fast until
/// `Retry-After` (default [defaultCooldown]) has passed.
final class HttpTodoistApi implements TodoistApi {
  /// Creates the client. [log] receives one line per request (operation and
  /// status only: no token, ids, titles or bodies).
  HttpTodoistApi({
    http.Client? client,
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 15),
    this._clock = const SystemClock(),
    this._log,
  }) : _client = client ?? http.Client(),
       _base = baseUrl ?? todoistApiBaseUrl;

  /// Wait after a 429 without `Retry-After`.
  static const defaultCooldown = Duration(seconds: 60);

  /// Longest wait honoured from `Retry-After`.
  static const maxCooldown = Duration(minutes: 30);

  /// Items per page requested, and the page limit per call (guards against
  /// a cursor that never ends).
  static const pageSize = 200;

  /// Most pages read per call.
  static const maxPages = 25;

  /// Time limit per request.
  final Duration timeout;

  final http.Client _client;
  final Uri _base;
  final Clock _clock;
  final void Function(String line)? _log;
  DateTime? _blockedUntil;

  static const _service = 'Todoist';

  @override
  Future<List<TodoistProject>> projects(String token) async {
    final rows = await _paged(token, 'projects', 'projects', const {});
    return [
      for (final p in rows)
        TodoistProject(
          id: _string(p, 'id'),
          name: _string(p, 'name'),
          inbox: p['inbox_project'] == true || p['is_inbox_project'] == true,
        ),
    ];
  }

  @override
  Future<List<TodoistTask>> tasks(String token, {String? projectId}) async {
    final rows = await _paged(token, 'tasks', 'tasks', {
      'project_id': ?projectId,
    });
    return rows.map(_task).toList();
  }

  @override
  Future<TodoistTask> addTask(
    String token, {
    required String content,
    String? projectId,
    String? dueString,
    int? priority,
  }) async {
    final json = await _send(
      token,
      'add',
      'POST',
      ['tasks'],
      body: {
        'content': content,
        'project_id': ?projectId,
        'due_string': ?dueString,
        'priority': ?priority,
      },
      notFound: '$_service-Projekt nicht gefunden',
    );
    return _task(_object(json));
  }

  @override
  Future<void> closeTask(String token, String id) =>
      _noContent(token, 'close', 'POST', ['tasks', id, 'close']);

  @override
  Future<void> reopenTask(String token, String id) =>
      _noContent(token, 'reopen', 'POST', ['tasks', id, 'reopen']);

  @override
  Future<void> deleteTask(String token, String id) =>
      _noContent(token, 'delete', 'DELETE', ['tasks', id]);

  Future<void> _noContent(
    String token,
    String op,
    String method,
    List<String> path,
  ) async {
    await _send(token, op, method, path, expectJson: false);
  }

  Future<List<Map<String, Object?>>> _paged(
    String token,
    String op,
    String path,
    Map<String, String> query,
  ) async {
    final all = <Map<String, Object?>>[];
    String? cursor;
    for (var page = 0; page < maxPages; page++) {
      final json = await _send(
        token,
        op,
        'GET',
        [path],
        query: {...query, 'limit': '$pageSize', 'cursor': ?cursor},
      );
      final List<Object?> raw;
      String? next;
      if (json is List<Object?>) {
        raw = json;
      } else {
        final map = _object(json);
        final results = map['results'];
        if (results is! List<Object?>) throw _malformed;
        raw = results;
        final n = map['next_cursor'];
        if (n != null && n is! String) throw _malformed;
        next = n as String?;
      }
      all.addAll(raw.map(_object));
      if (next == null || next.isEmpty) return all;
      cursor = next;
    }
    return all;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  TodoistTask _task(Map<String, Object?> t) {
    String? date;
    String? time;
    final due = t['due'];
    if (due != null) {
      final d = _object(due);
      final datetime = d['datetime'];
      final plain = d['date'];
      final raw = datetime is String ? datetime : plain;
      if (raw is String && raw.length >= 10) {
        date = raw.substring(0, 10);
        if (raw.length >= 16 && raw[10] == 'T') {
          time = raw.substring(11, 16);
          final zoned = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(raw);
          final zone = d['timezone'];
          if (zoned && zone is String && zone.isNotEmpty) {
            // Fixed-zone due time: show the wall clock in its own zone.
            try {
              final l = tz.TZDateTime.from(
                DateTime.parse(raw),
                timeZoneLocation(zone),
              );
              date =
                  '${l.year.toString().padLeft(4, '0')}-${_two(l.month)}-'
                  '${_two(l.day)}';
              time = '${_two(l.hour)}:${_two(l.minute)}';
            } on Object {
              // Unknown zone name or odd format: keep the plain parts.
            }
          }
        }
      } else if (raw != null) {
        throw _malformed;
      }
    }
    final prio = t['priority'];
    return TodoistTask(
      id: _string(t, 'id'),
      content: _string(t, 'content'),
      projectId: _string(t, 'project_id'),
      dueDate: date,
      dueTime: time,
      priority: prio is int && prio >= 1 && prio <= 4 ? prio : 1,
      recurring: due != null && _object(due)['is_recurring'] == true,
    );
  }

  Future<Object?> _send(
    String token,
    String operation,
    String method,
    List<String> path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    String notFound = '$_service: Aufgabe nicht gefunden',
    bool expectJson = true,
  }) async {
    final blocked = _blockedUntil;
    if (blocked != null) {
      if (_clock.now().isBefore(blocked)) {
        _log?.call('$_service $operation → gesperrt (Anfragelimit)');
        throw _rateLimited;
      }
      _blockedUntil = null;
    }
    final url = _base.replace(
      pathSegments: [..._base.pathSegments.where((s) => s.isNotEmpty), ...path],
      queryParameters: query,
    );
    final request = http.Request(method, url)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      _log?.call('$_service $operation → Zeitüberschreitung');
      throw const PortException(
        PortErrorKind.unavailable,
        '$_service antwortet nicht (Zeitüberschreitung)',
      );
    } on http.ClientException {
      throw _unreachable(operation);
    } on IOException {
      throw _unreachable(operation);
    }
    final status = response.statusCode;
    _log?.call('$_service $operation → $status');
    if (status == 401 || status == 403) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        '$_service-Zugang abgelehnt: Token ungültig oder widerrufen (HTTP 401/403)',
      );
    }
    if (status == 404) throw PortException(PortErrorKind.notFound, notFound);
    if (status == 400) {
      throw const PortException(
        PortErrorKind.rejected,
        '$_service hat die Eingabe abgelehnt (z. B. Fälligkeit nicht '
        'verständlich)',
      );
    }
    if (status == 429) {
      _blockedUntil = _clock.now().add(_retryAfter(response.headers));
      throw _rateLimited;
    }
    if (status >= 500) {
      throw PortException(
        PortErrorKind.unavailable,
        '$_service hat einen Serverfehler (HTTP $status)',
      );
    }
    if (status < 200 || status >= 300) {
      throw PortException(
        PortErrorKind.failed,
        '$_service: unerwartete Antwort (HTTP $status)',
      );
    }
    if (!expectJson) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw _malformed;
    }
  }

  PortException _unreachable(String operation) {
    _log?.call('$_service $operation → nicht erreichbar');
    return const PortException(
      PortErrorKind.unavailable,
      '$_service ist nicht erreichbar',
    );
  }

  Duration _retryAfter(Map<String, String> headers) {
    final seconds = int.tryParse(headers['retry-after']?.trim() ?? '');
    if (seconds == null || seconds < 0) return defaultCooldown;
    final d = Duration(seconds: seconds);
    return d > maxCooldown ? maxCooldown : d;
  }

  static const _rateLimited = PortException(
    PortErrorKind.unavailable,
    '$_service: Anfragelimit erreicht, später erneut versuchen',
  );

  static const _malformed = PortException(
    PortErrorKind.failed,
    '$_service: unerwartete Antwort (Format geändert?)',
  );

  static Map<String, Object?> _object(Object? json) =>
      json is Map<String, Object?> ? json : throw _malformed;

  static String _string(Map<String, Object?> map, String key) {
    final v = map[key];
    if (v is! String || v.isEmpty) throw _malformed;
    return v;
  }
}
