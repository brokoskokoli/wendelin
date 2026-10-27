import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import 'spotify_api.dart';

/// Base URL of the Spotify Web API.
final spotifyApiBaseUrl = Uri.parse('https://api.spotify.com/v1/');

/// Token endpoint of Spotify Accounts.
final spotifyTokenUrl = Uri.parse('https://accounts.spotify.com/api/token');

/// [SpotifyApi] over HTTPS (official Web API, OAuth with PKCE).
///
/// No request is repeated automatically. After HTTP 429 every call fails
/// fast with `PortException(unavailable)` until `Retry-After` (default
/// [defaultCooldown]) has passed.
final class HttpSpotifyApi implements SpotifyApi {
  /// Creates the client. [log] receives one line per request (operation and
  /// status only: no headers, ids, bodies or tokens).
  HttpSpotifyApi({
    http.Client? client,
    Uri? baseUrl,
    Uri? tokenUrl,
    this.timeout = const Duration(seconds: 15),
    this._clock = const SystemClock(),
    this._log,
  }) : _client = client ?? http.Client(),
       _base = baseUrl ?? spotifyApiBaseUrl,
       _tokenUrl = tokenUrl ?? spotifyTokenUrl;

  /// Wait after a 429 without `Retry-After`.
  static const defaultCooldown = Duration(seconds: 30);

  /// Longest wait honoured from `Retry-After`.
  static const maxCooldown = Duration(minutes: 10);

  final http.Client _client;
  final Uri _base;
  final Uri _tokenUrl;
  final Clock _clock;
  final void Function(String line)? _log;

  /// Time limit per request.
  final Duration timeout;

  DateTime? _blockedUntil;

  static const _service = 'Spotify';

  static const _malformed = PortException(
    PortErrorKind.failed,
    '$_service: unerwartete Antwort (Format geändert?)',
  );

  static const _rateLimited = PortException(
    PortErrorKind.unavailable,
    '$_service: Anfragelimit erreicht, später erneut versuchen',
  );

  @override
  Future<SpotifyAuth> exchangeCode({
    required String clientId,
    required String code,
    required String verifier,
    required Uri redirect,
  }) async {
    final json = await _token('login', {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirect.toString(),
      'client_id': clientId,
      'code_verifier': verifier,
    });
    return _auth(json, null);
  }

  @override
  Future<SpotifyAuth> refresh(String clientId, SpotifyAuth auth) async {
    final json = await _token('refresh', {
      'grant_type': 'refresh_token',
      'refresh_token': auth.refreshToken,
      'client_id': clientId,
    });
    return _auth(json, auth.refreshToken);
  }

  SpotifyAuth _auth(Map<String, Object?> json, String? oldRefresh) {
    final access = json['access_token'];
    final refresh = json['refresh_token'] ?? oldRefresh;
    final seconds = json['expires_in'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        seconds is! int) {
      throw _malformed;
    }
    return SpotifyAuth(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: _clock.now().add(Duration(seconds: seconds)),
    );
  }

  Future<Map<String, Object?>> _token(
    String operation,
    Map<String, String> form,
  ) async {
    final response = await _send(
      operation,
      http.Request('POST', _tokenUrl)..bodyFields = form,
    );
    final status = response.statusCode;
    if (status == 400 || status == 401) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        '$_service-Anmeldung abgelehnt oder abgelaufen (Client-ID und '
        'Weiterleitungsadresse in der Entwickler-App prüfen)',
      );
    }
    _throwOnStatus(response, operation);
    return _object(_decode(response));
  }

  @override
  Future<List<SpotifyItem>> search(
    SpotifyAuth auth,
    String query,
    Set<SpotifyKind> kinds, {
    int limit = 5,
  }) async {
    final url = _url(
      ['search'],
      {
        'q': query,
        'type': kinds.map((k) => k.name).join(','),
        'limit': '$limit',
      },
    );
    final map = _object(_decode(await _call('search', 'GET', url, auth)));
    final items = <SpotifyItem>[];
    for (final kind in SpotifyKind.values) {
      final page = map['${kind.name}s'];
      if (page == null) continue;
      final raw = _object(page)['items'];
      if (raw is! List<Object?>) throw _malformed;
      for (final e in raw) {
        // Playlists can contain null entries.
        if (e == null) continue;
        final item = _item(kind, _object(e));
        if (item != null) items.add(item);
      }
    }
    return items;
  }

  SpotifyItem? _item(SpotifyKind kind, Map<String, Object?> m) {
    final uri = m['uri'];
    final name = m['name'];
    if (uri is! String || name is! String || !spotifyUriPattern.hasMatch(uri)) {
      return null;
    }
    final by = switch (kind) {
      SpotifyKind.track || SpotifyKind.album => _names(m['artists']),
      SpotifyKind.playlist => _optString(_obj(m['owner']), 'display_name'),
      SpotifyKind.artist => null,
    };
    return SpotifyItem(kind: kind, uri: uri, name: name, by: by);
  }

  @override
  Future<SpotifyPlayback?> playback(SpotifyAuth auth) async {
    final response = await _call(
      'playback',
      'GET',
      _url(['me', 'player'], {'additional_types': 'episode'}),
      auth,
    );
    if (response.statusCode == 204 || response.bodyBytes.isEmpty) return null;
    final m = _object(_decode(response));
    final item = _obj(m['item']);
    final isEpisode = item['type'] == 'episode';
    final uri = item['uri'];
    return SpotifyPlayback(
      isPlaying: m['is_playing'] == true,
      title: _optString(item, 'name'),
      by: isEpisode
          ? _optString(_obj(item['show']), 'name')
          : _names(item['artists']),
      album: _optString(_obj(item['album']), 'name'),
      trackUri: !isEpisode && uri is String && spotifyUriPattern.hasMatch(uri)
          ? uri
          : null,
      contextUri: _optString(_obj(m['context']), 'uri'),
      progressMs: m['progress_ms'] is int ? m['progress_ms'] as int : null,
      deviceName: _optString(_obj(m['device']), 'name'),
      deviceId: _optString(_obj(m['device']), 'id'),
    );
  }

  @override
  Future<List<SpotifyDevice>> devices(SpotifyAuth auth) async {
    final map = _object(
      _decode(
        await _call('devices', 'GET', _url(['me', 'player', 'devices']), auth),
      ),
    );
    final raw = map['devices'];
    if (raw is! List<Object?>) throw _malformed;
    return [
      for (final e in raw)
        if (_obj(e)
            case {'id': final String id, 'name': final String name} && final d)
          _device(id, name, d),
    ];
  }

  @override
  Future<void> play(
    SpotifyAuth auth, {
    String? deviceId,
    List<String>? uris,
    String? contextUri,
    String? offsetUri,
    int? positionMs,
  }) async {
    final body = <String, Object?>{
      'uris': ?uris,
      'context_uri': ?contextUri,
      if (contextUri != null && offsetUri != null) 'offset': {'uri': offsetUri},
      'position_ms': ?positionMs,
    };
    await _call(
      'play',
      'PUT',
      _player('play', deviceId),
      auth,
      body: body.isEmpty ? null : jsonEncode(body),
    );
  }

  @override
  Future<void> pause(SpotifyAuth auth, {String? deviceId}) async {
    await _call('pause', 'PUT', _player('pause', deviceId), auth);
  }

  @override
  Future<void> next(SpotifyAuth auth, {String? deviceId}) async {
    await _call('next', 'POST', _player('next', deviceId), auth);
  }

  @override
  Future<void> previous(SpotifyAuth auth, {String? deviceId}) async {
    await _call('previous', 'POST', _player('previous', deviceId), auth);
  }

  @override
  Future<void> queueAdd(
    SpotifyAuth auth,
    String uri, {
    String? deviceId,
  }) async {
    final url = _url(
      ['me', 'player', 'queue'],
      {'uri': uri, 'device_id': ?deviceId},
    );
    await _call('queue', 'POST', url, auth);
  }

  Uri _player(String command, String? deviceId) =>
      _url(['me', 'player', command], {'device_id': ?deviceId});

  Uri _url(List<String> segments, [Map<String, String> query = const {}]) =>
      _base.replace(
        pathSegments: [
          ..._base.pathSegments.where((s) => s.isNotEmpty),
          ...segments,
        ],
        queryParameters: query.isEmpty ? null : query,
      );

  Future<http.Response> _call(
    String operation,
    String method,
    Uri url,
    SpotifyAuth auth, {
    String? body,
  }) async {
    final request = http.Request(method, url)
      ..headers['Authorization'] = 'Bearer ${auth.accessToken}'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = body;
    }
    final response = await _send(operation, request);
    _throwOnStatus(response, operation);
    return response;
  }

  Future<http.Response> _send(String operation, http.Request request) async {
    final blocked = _blockedUntil;
    if (blocked != null) {
      if (_clock.now().isBefore(blocked)) {
        _log?.call('$_service $operation → gesperrt (Anfragelimit)');
        throw _rateLimited;
      }
      _blockedUntil = null;
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
    _log?.call('$_service $operation → ${response.statusCode}');
    if (response.statusCode == 429) {
      _blockedUntil = _clock.now().add(_retryAfter(response.headers));
      throw _rateLimited;
    }
    return response;
  }

  void _throwOnStatus(http.Response response, String operation) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    switch (status) {
      case 401:
        throw const PortException(
          PortErrorKind.permissionDenied,
          '$_service-Sitzung abgelaufen oder abgelehnt (HTTP 401)',
        );
      case 403:
        throw _forbidden(_reason(response));
      case 404:
        throw _reason(response) == 'NO_ACTIVE_DEVICE'
            ? spotifyNoDevice
            : const PortException(
                PortErrorKind.notFound,
                '$_service: nicht gefunden (HTTP 404)',
              );
      case >= 500:
        throw PortException(
          PortErrorKind.unavailable,
          '$_service hat einen Serverfehler (HTTP $status)',
        );
      default:
        throw PortException(
          PortErrorKind.failed,
          '$_service: unerwartete Antwort (HTTP $status)',
        );
    }
  }

  PortException _forbidden(String? reason) => switch (reason) {
    'PREMIUM_REQUIRED' => spotifyPremiumRequired,
    'NO_ACTIVE_DEVICE' => spotifyNoDevice,
    _ => const PortException(
      PortErrorKind.rejected,
      '$_service verweigert den Zugriff oder den Befehl (HTTP 403). Im '
      'Entwickler-Dashboard muss das Konto unter „User Management“ '
      'eingetragen sein; manche Befehle gehen nicht, wenn gerade nichts '
      'passt (z. B. Pause bei Pause).',
    ),
  };

  /// `error.reason` of a Web API error body, if there is one.
  static String? _reason(http.Response response) {
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is Map<String, Object?>) {
        final error = json['error'];
        if (error is Map<String, Object?> && error['reason'] is String) {
          return error['reason'] as String;
        }
      }
    } on FormatException {
      // No JSON body: no reason.
    }
    return null;
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

  static Object? _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw _malformed;
    }
  }

  static Map<String, Object?> _object(Object? json) =>
      json is Map<String, Object?> ? json : throw _malformed;

  /// [json] as a map, or an empty map (absent or `null` parts).
  static Map<String, Object?> _obj(Object? json) =>
      json is Map<String, Object?> ? json : const {};

  static String? _optString(Map<String, Object?> map, String key) {
    final v = map[key];
    return v is String ? v : null;
  }

  static String? _names(Object? artists) {
    if (artists is! List<Object?>) return null;
    final names = [for (final a in artists) ?_optString(_obj(a), 'name')];
    return names.isEmpty ? null : names.join(', ');
  }
}

SpotifyDevice _device(String id, String name, Map<String, Object?> d) {
  final type = d['type'];
  return SpotifyDevice(
    id: id,
    name: name,
    isActive: d['is_active'] == true,
    isRestricted: d['is_restricted'] == true,
    type: type is String ? type : null,
  );
}
