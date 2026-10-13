import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import 'bring_api.dart';

/// Client key the Bring! apps send in `X-BRING-API-KEY`. Not a user secret:
/// it is the same for every installation and is published in the
/// open-source clients (see the README, „Quelle“).
const bringPublicApiKey = 'cof4Nc6D8saplXjE3h3HXqHH8m7VU2i1Gs0g85Sp';

/// Default base URL of the Bring! REST API.
final bringApiBaseUrl = Uri.parse('https://api.getbring.com/rest/');

/// [BringApi] over HTTPS against the unofficial Bring! REST API.
///
/// Endpoints and fields follow the open-source Python client `bring-api`
/// (github.com/miaucl/bring-api), which the Home Assistant integration
/// uses; details in the README. No request is repeated automatically.
/// After HTTP 429 every call fails fast with `PortException(unavailable)`
/// until `Retry-After` (default [defaultCooldown]) has passed.
final class HttpBringApi implements BringApi {
  /// Creates the client. [log] receives one line per request (operation and
  /// status only: no headers, ids, bodies or tokens).
  HttpBringApi({
    http.Client? client,
    Uri? baseUrl,
    this.apiKey = bringPublicApiKey,
    this.country = 'DE',
    this.timeout = const Duration(seconds: 15),
    this._clock = const SystemClock(),
    this._log,
  }) : _client = client ?? http.Client(),
       _base = baseUrl ?? bringApiBaseUrl;

  /// Wait after a 429 without `Retry-After`.
  static const defaultCooldown = Duration(seconds: 60);

  /// Longest wait honoured from `Retry-After`.
  static const maxCooldown = Duration(minutes: 30);

  final http.Client _client;
  final Uri _base;
  final Clock _clock;
  final void Function(String line)? _log;

  /// Value of `X-BRING-API-KEY`.
  final String apiKey;

  /// Value of `X-BRING-COUNTRY`.
  final String country;

  /// Time limit per request.
  final Duration timeout;

  DateTime? _blockedUntil;

  static const _service = 'Bring!';

  Map<String, String> _headers([BringAuth? auth]) => {
    'X-BRING-API-KEY': apiKey,
    'X-BRING-CLIENT': 'android',
    'X-BRING-APPLICATION': 'bring',
    'X-BRING-COUNTRY': country,
    'Accept': 'application/json',
    if (auth != null) ...{
      'Authorization': 'Bearer ${auth.accessToken}',
      'X-BRING-USER-UUID': auth.userUuid,
      if (auth.publicUuid != null) 'X-BRING-PUBLIC-USER-UUID': auth.publicUuid!,
    },
  };

  Uri _url(List<String> segments) => _base.replace(
    pathSegments: [
      ..._base.pathSegments.where((s) => s.isNotEmpty),
      ...segments,
    ],
  );

  @override
  Future<BringAuth> login(String email, String password) async {
    final json = await _send(
      'login',
      'POST',
      _url(['v2', 'bringauth']),
      headers: _headers(),
      form: {'email': email, 'password': password},
      authMessage: '$_service-Anmeldung abgelehnt: E-Mail oder Passwort falsch',
      badRequestIsAuth: true,
    );
    final map = _object(json);
    return BringAuth(
      userUuid: _string(map, 'uuid'),
      accessToken: _string(map, 'access_token'),
      refreshToken: _optString(map, 'refresh_token'),
      publicUuid: _optString(map, 'publicUuid'),
      defaultListUuid: _optString(map, 'bringListUUID'),
    );
  }

  @override
  Future<BringAuth> refresh(BringAuth auth) async {
    final token = auth.refreshToken;
    if (token == null || token.isEmpty) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        '$_service-Sitzung abgelaufen (keine Erneuerung möglich)',
      );
    }
    final json = await _send(
      'refresh',
      'POST',
      _url(['v2', 'bringauth', 'token']),
      headers: _headers(auth),
      form: {'grant_type': 'refresh_token', 'refresh_token': token},
      authMessage: '$_service-Sitzung abgelaufen, Erneuerung abgelehnt',
      badRequestIsAuth: true,
    );
    final map = _object(json);
    return auth.withTokens(
      accessToken: _string(map, 'access_token'),
      refreshToken: _optString(map, 'refresh_token'),
    );
  }

  @override
  Future<List<BringList>> lists(BringAuth auth) async {
    final json = await _send(
      'lists',
      'GET',
      _url(['bringusers', auth.userUuid, 'lists']),
      headers: _headers(auth),
    );
    final raw = _object(json)['lists'];
    if (raw is! List<Object?>) throw _malformed;
    return [
      for (final e in raw)
        BringList(
          uuid: _string(_object(e), 'listUuid'),
          name: _string(_object(e), 'name'),
        ),
    ];
  }

  @override
  Future<BringItems> items(BringAuth auth, String listUuid) async {
    final json = await _send(
      'items',
      'GET',
      _url(['v2', 'bringlists', listUuid]),
      headers: _headers(auth),
      notFoundMessage: '$_service-Liste nicht gefunden',
    );
    final items = _object(_object(json)['items']);
    List<BringItem> read(String key) {
      final raw = items[key];
      if (raw == null) return const [];
      if (raw is! List<Object?>) throw _malformed;
      return [
        for (final e in raw)
          BringItem(
            name: _string(_object(e), 'itemId'),
            spec: _optString(_object(e), 'specification') ?? '',
            uuid: _optString(_object(e), 'uuid'),
          ),
      ];
    }

    return BringItems(purchase: read('purchase'), recently: read('recently'));
  }

  @override
  Future<void> saveItem(BringAuth auth, String listUuid, BringItem item) =>
      _change(auth, listUuid, item, 'TO_PURCHASE', item.spec);

  @override
  Future<void> removeItem(BringAuth auth, String listUuid, BringItem item) =>
      _change(auth, listUuid, item, 'REMOVE', '');

  @override
  Future<void> completeItem(BringAuth auth, String listUuid, BringItem item) =>
      _change(auth, listUuid, item, 'TO_RECENTLY', item.spec);

  Future<void> _change(
    BringAuth auth,
    String listUuid,
    BringItem item,
    String operation,
    String spec,
  ) async {
    await _send(
      operation.toLowerCase(),
      'PUT',
      _url(['v2', 'bringlists', listUuid, 'items']),
      headers: {..._headers(auth), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'changes': [
          {
            'accuracy': '0.0',
            'altitude': '0.0',
            'latitude': '0.0',
            'longitude': '0.0',
            'itemId': item.name,
            'spec': spec,
            if (item.uuid != null) 'uuid': item.uuid,
            'operation': operation,
          },
        ],
        'sender': '',
      }),
      notFoundMessage: '$_service-Liste nicht gefunden',
      expectJson: false,
    );
  }

  /// Sends one request and returns the decoded JSON (or `null` with
  /// [expectJson] false). Every failure becomes a [PortException].
  Future<Object?> _send(
    String operation,
    String method,
    Uri url, {
    required Map<String, String> headers,
    Map<String, String>? form,
    String? body,
    String authMessage =
        '$_service-Sitzung abgelaufen oder Zugang abgelehnt (HTTP 401/403)',
    bool badRequestIsAuth = false,
    String notFoundMessage = '$_service: Adresse nicht gefunden (HTTP 404)',
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
    final request = http.Request(method, url)..headers.addAll(headers);
    if (form != null) request.bodyFields = form;
    if (body != null) request.body = body;
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
    if (status == 401 || status == 403 || (badRequestIsAuth && status == 400)) {
      throw PortException(PortErrorKind.permissionDenied, authMessage);
    }
    if (status == 404) {
      throw PortException(PortErrorKind.notFound, notFoundMessage);
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

  static String? _optString(Map<String, Object?> map, String key) {
    final v = map[key];
    if (v == null) return null;
    if (v is! String) throw _malformed;
    return v;
  }
}
