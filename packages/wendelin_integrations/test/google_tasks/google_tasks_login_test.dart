import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

const _id = 'abc-123.apps.googleusercontent.com';
const _secret = 'GOCSPX-secret-canary';

Future<int> _get(Uri uri, {String? host}) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(uri);
    if (host != null) req.headers.host = host;
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    c.close(force: true);
  }
}

void main() {
  late FakeGoogleTasksApi store;
  late FakeGoogleBrowser browser;
  late GoogleTasksLogin login;
  late _SpyOAuth oauth;

  /// What the "browser" does after the login page opened: calls the
  /// redirect with the query [answer] builds from the login address.
  void answer(Map<String, String> Function(Uri login) build) {
    browser.onOpen = (url) async {
      final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
      await _get(redirect.replace(queryParameters: build(url)));
    };
  }

  setUp(() {
    store = FakeGoogleTasksApi()
      ..storedClient = null
      ..storedRefresh = null;
    oauth = _SpyOAuth(store);
    browser = FakeGoogleBrowser();
    login = GoogleTasksLogin(
      oauth,
      store,
      browser,
      random: Random(1),
      timeout: const Duration(seconds: 5),
    );
  });

  Future<String?> signIn() => login.signIn(_id, _secret);

  test(
    'Erfolg: PKCE S256, state, Loopback; speichert Client und Token',
    () async {
      answer(
        (u) => {'state': u.queryParameters['state']!, 'code': 'fake-code'},
      );
      expect(await signIn(), isNull);
      final url = browser.opened.single;
      final q = url.queryParameters;
      expect(url.host, 'accounts.google.com');
      expect(q['response_type'], 'code');
      expect(q['client_id'], _id);
      expect(q['scope'], googleTasksScope);
      expect(q['code_challenge_method'], 'S256');
      expect(q['access_type'], 'offline');
      final redirect = Uri.parse(q['redirect_uri']!);
      expect(redirect.scheme, 'http');
      expect(redirect.host, '127.0.0.1');
      expect(redirect.port, greaterThan(0));
      expect(redirect.path, '/oauth2/callback');
      expect(q['state']!.length, greaterThanOrEqualTo(32));
      // Der gesendete Verifier gehört zur Challenge der Login-Adresse.
      expect(pkceChallengeOf(oauth.verifier!), q['code_challenge']);
      expect(oauth.redirect, redirect);
      expect(store.storedClient, const GoogleClient(id: _id, secret: _secret));
      expect(store.storedRefresh, FakeGoogleTasksApi.validRefresh);
    },
  );

  test(
    'falscher state: eigene Meldung, kein Tausch, nichts gespeichert',
    () async {
      answer((u) => {'state': 'fremd', 'code': 'fake-code'});
      final m = await signIn();
      expect(m, contains('state stimmt nicht'));
      expect(m, isNot(contains('abgebrochen: Zugriff')));
      expect(oauth.exchanged, isFalse);
      expect(store.storedRefresh, isNull);
      expect(store.storedClient, isNull);
    },
  );

  test('fehlender state zählt wie falscher state', () async {
    answer((u) => {'code': 'fake-code'});
    expect(await signIn(), contains('state stimmt nicht'));
    expect(oauth.exchanged, isFalse);
  });

  test('access_denied, anderer Fehler, kein Code: je eigene Meldung', () async {
    answer(
      (u) => {'state': u.queryParameters['state']!, 'error': 'access_denied'},
    );
    final denied = await signIn();
    expect(denied, contains('Zugriff nicht erlaubt'));
    answer(
      (u) => {'state': u.queryParameters['state']!, 'error': 'server_error'},
    );
    final other = await signIn();
    expect(other, contains('abgelehnt (server_error)'));
    answer((u) => {'state': u.queryParameters['state']!, 'error': '<b>x</b>'});
    expect(await signIn(), isNot(contains('<b>')));
    answer((u) => {'state': u.queryParameters['state']!});
    final none = await signIn();
    expect(none, contains('keinen Code'));
    expect({denied, other, none}, hasLength(3));
    expect(oauth.exchanged, isFalse);
  });

  test('Zeitüberschreitung: eigene Meldung, Server geschlossen', () async {
    login = GoogleTasksLogin(
      oauth,
      store,
      browser,
      timeout: const Duration(milliseconds: 30),
    );
    Uri? redirect;
    browser.onOpen = (u) async =>
        redirect = Uri.parse(u.queryParameters['redirect_uri']!);
    final m = await login.signIn(_id, _secret);
    expect(m, contains('Zeitüberschreitung'));
    expect(m, isNot(contains('state')));
    await expectLater(_get(redirect!), throwsA(isA<SocketException>()));
  });

  test('Abbruch durch cancel()', () async {
    browser.onOpen = (u) async => unawaited(login.cancel());
    expect(await signIn(), 'Anmeldung abgebrochen.');
    expect(store.storedRefresh, isNull);
  });

  test('kein Browser', () async {
    browser.available = false;
    expect(await signIn(), contains('kein Browser'));
  });

  test(
    'Eingaben: Client-ID und Secret werden geprüft, ohne den Browser',
    () async {
      expect(
        await login.signIn('abc', _secret),
        contains('apps.googleusercontent.com'),
      );
      expect(await login.signIn(_id, '  '), contains('Client-Secret'));
      expect(browser.opened, isEmpty);
    },
  );

  test('Server nimmt genau eine Anfrage auf dem Pfad an', () async {
    final r = await LoopbackReceiver.start();
    final redirect = r.redirect;
    expect(r.redirect.host, '127.0.0.1');
    expect(r.address, InternetAddress.loopbackIPv4);
    final wait = r.wait(const Duration(seconds: 5));
    expect(await _get(redirect.replace(path: '/favicon.ico')), 404);
    expect(await _get(redirect, host: 'evil.example'), 404);
    expect(await _get(redirect.replace(queryParameters: {'code': 'c'})), 200);
    expect((await wait).queryParameters, {'code': 'c'});
    await expectLater(_get(redirect), throwsA(isA<SocketException>()));
  });

  test(
    'Token-Tausch schlägt fehl: Meldung ohne Secrets, nichts gespeichert',
    () async {
      answer((u) => {'state': u.queryParameters['state']!, 'code': 'falsch'});
      final m = await signIn();
      expect(m, contains('abgelehnt'));
      expect(m, isNot(anyOf(contains(_secret), contains('falsch'))));
      expect(store.storedRefresh, isNull);
      expect(store.storedClient, isNull);
    },
  );

  test('Abmelden: Token widerrufen, alles gelöscht', () async {
    store
      ..storedClient = const GoogleClient(id: _id, secret: _secret)
      ..storedRefresh = FakeGoogleTasksApi.validRefresh;
    await login.signOut();
    expect(store.revoked, [FakeGoogleTasksApi.validRefresh]);
    expect(store.storedClient, isNull);
    expect(store.storedRefresh, isNull);
  });

  test('Abmelden löscht auch, wenn der Widerruf scheitert', () async {
    store
      ..storedClient = const GoogleClient(id: _id, secret: _secret)
      ..storedRefresh = 'r';
    await GoogleTasksLogin(_ThrowingRevoke(store), store, browser).signOut();
    expect(store.storedClient, isNull);
    expect(store.storedRefresh, isNull);
  });
}

/// Independent S256 computation (RFC 7636).
String pkceChallengeOf(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

/// Records what the exchange received.
class _SpyOAuth implements GoogleOAuthApi {
  _SpyOAuth(this.inner);
  final FakeGoogleTasksApi inner;
  String? verifier;
  Uri? redirect;
  bool exchanged = false;

  @override
  Future<GoogleTokenSet> exchangeCode({
    required GoogleClient client,
    required String code,
    required String verifier,
    required Uri redirect,
  }) {
    exchanged = true;
    this.verifier = verifier;
    this.redirect = redirect;
    return inner.exchangeCode(
      client: client,
      code: code,
      verifier: verifier,
      redirect: redirect,
    );
  }

  @override
  Future<GoogleTokenSet> refresh(GoogleClient client, String refreshToken) =>
      inner.refresh(client, refreshToken);

  @override
  Future<void> revoke(String token) => inner.revoke(token);
}

class _ThrowingRevoke extends _SpyOAuth {
  _ThrowingRevoke(super.inner);
  @override
  Future<void> revoke(String token) => throw StateError('weg');
}
