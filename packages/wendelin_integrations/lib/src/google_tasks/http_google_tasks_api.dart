import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import 'google_tasks_api.dart';

/// Default base URL of the Tasks API.
final googleTasksBaseUrl = Uri.parse('https://tasks.googleapis.com/tasks/v1/');

/// [GoogleTasksApi] over HTTPS. Lists are paginated with `nextPageToken`.
/// No request is repeated automatically. After HTTP 429 every call fails
/// fast until `Retry-After` (default [defaultCooldown]) has passed.
final class HttpGoogleTasksApi implements GoogleTasksApi {
  /// Creates the client. [log] receives one line per request (operation and
  /// status only: no token, ids, titles or bodies).
  HttpGoogleTasksApi({
    http.Client? client,
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 15),
    this._clock = const SystemClock(),
    this._log,
  }) : _client = client ?? http.Client(),
       _base = baseUrl ?? googleTasksBaseUrl;

  /// Wait after a 429 without `Retry-After`.
  static const defaultCooldown = Duration(seconds: 60);

  /// Longest wait honoured from `Retry-After`.
  static const maxCooldown = Duration(minutes: 30);

  /// Items per page requested (the API maximum), and the page limit per
  /// call (guards against a token that never ends).
  static const pageSize = 100;

  /// Most pages read per call.
  static const maxPages = 25;

  /// Time limit per request.
  final Duration timeout;

  final http.Client _client;
  final Uri _base;
  final Clock _clock;
  final void Function(String line)? _log;
  DateTime? _blockedUntil;

  static const _service = 'Google Tasks';

  @override
  Future<List<GoogleTaskList>> taskLists(String accessToken) async {
    final rows = await _paged(accessToken, 'lists', [
      'users',
      '@me',
      'lists',
    ], const {});
    return [
      for (final r in rows)
        GoogleTaskList(
          id: _string(r, 'id'),
          title: r['title'] as String? ?? '',
        ),
    ];
  }

  @override
  Future<List<GoogleTask>> tasks(String accessToken, String listId) async {
    final rows = await _paged(
      accessToken,
      'tasks',
      ['lists', listId, 'tasks'],
      const {'showCompleted': 'false', 'showHidden': 'false'},
    );
    return [
      for (final r in rows)
        if (r['status'] != 'completed') _task(listId, r),
    ];
  }

  @override
  Future<GoogleTask> addTask(
    String accessToken,
    String listId, {
    required String title,
    String? due,
  }) async {
    final json = await _send(
      accessToken,
      'add',
      'POST',
      ['lists', listId, 'tasks'],
      body: {
        'title': title,
        'due': ?(due == null ? null : '${due}T00:00:00.000Z'),
      },
      notFound: '$_service-Liste nicht gefunden',
    );
    return _task(listId, _object(json));
  }

  @override
  Future<void> setCompleted(
    String accessToken,
    String listId,
    String taskId, {
    required bool completed,
  }) async {
    await _send(
      accessToken,
      completed ? 'complete' : 'reopen',
      'PATCH',
      ['lists', listId, 'tasks', taskId],
      body: completed
          ? {'status': 'completed'}
          : {'status': 'needsAction', 'completed': null},
    );
  }

  @override
  Future<void> deleteTask(
    String accessToken,
    String listId,
    String taskId,
  ) async {
    await _send(accessToken, 'delete', 'DELETE', [
      'lists',
      listId,
      'tasks',
      taskId,
    ], expectJson: false);
  }

  Future<List<Map<String, Object?>>> _paged(
    String token,
    String op,
    List<String> path,
    Map<String, String> query,
  ) async {
    final all = <Map<String, Object?>>[];
    String? next;
    for (var page = 0; page < maxPages; page++) {
      final map = _object(
        await _send(
          token,
          op,
          'GET',
          path,
          query: {...query, 'maxResults': '$pageSize', 'pageToken': ?next},
        ),
      );
      final items = map['items'];
      if (items != null) {
        if (items is! List<Object?>) throw _malformed;
        all.addAll(items.map(_object));
      }
      final n = map['nextPageToken'];
      if (n != null && n is! String) throw _malformed;
      if (n == null || (n as String).isEmpty) return all;
      next = n;
    }
    return all;
  }

  GoogleTask _task(String listId, Map<String, Object?> t) {
    final due = t['due'];
    String? date;
    if (due != null) {
      if (due is! String || due.length < 10) throw _malformed;
      date = due.substring(0, 10);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) throw _malformed;
    }
    return GoogleTask(
      id: _string(t, 'id'),
      listId: listId,
      title: t['title'] as String? ?? '',
      due: date,
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
    if (status == 401) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        '$_service-Zugang abgelehnt: Anmeldung abgelaufen (HTTP 401)',
      );
    }
    if (status == 403) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        '$_service-Zugriff verweigert (HTTP 403): Tasks API im '
        'Cloud-Projekt aktiviert und Aufgaben-Zugriff erlaubt?',
      );
    }
    if (status == 404) throw PortException(PortErrorKind.notFound, notFound);
    if (status == 400) {
      throw const PortException(
        PortErrorKind.rejected,
        '$_service hat die Eingabe abgelehnt',
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
