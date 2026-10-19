import 'dart:math';

import 'package:test/test.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

const _clientId = '0123456789abcdef0123456789abcdef';

void main() {
  late FakeSpotifyApi api;
  late FakeSpotifySecrets secrets;
  late FakeSpotifyAuthBrowser browser;
  late SpotifyLogin login;

  setUp(() {
    api = FakeSpotifyApi();
    secrets = FakeSpotifySecrets();
    browser = FakeSpotifyAuthBrowser();
    login = SpotifyLogin(api, secrets, browser, random: Random(7));
  });

  test('PKCE-Challenge nach RFC 7636, Anhang B', () {
    expect(
      spotifyChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('Erfolg: Anmeldeadresse mit PKCE, State, Scopes; Client-ID und Token '
      'gespeichert', () async {
    expect(await login.signIn(' $_clientId '), isNull);
    final url = browser.opened.single;
    expect(url.host, 'accounts.spotify.com');
    expect(url.path, '/authorize');
    final q = url.queryParameters;
    expect(q['response_type'], 'code');
    expect(q['client_id'], _clientId);
    expect(q['redirect_uri'], 'app.wendelin://oauth/spotify');
    expect(q['code_challenge_method'], 'S256');
    expect(q['code_challenge'], isNotEmpty);
    expect(q['state'], hasLength(32));
    expect(q['scope'], contains('user-modify-playback-state'));
    expect(q['scope'], contains('user-read-playback-state'));
    expect(q.containsKey('client_secret'), isFalse);
    expect(await secrets.clientId(), _clientId);
    expect((await secrets.auth())!.accessToken, api.currentAccess);
  });

  test('Verifier passt zur Challenge der Anmeldeadresse', () async {
    String? verifier;
    final spy = _SpyApi(api, (v) => verifier = v);
    final l = SpotifyLogin(spy, secrets, browser, random: Random(1));
    await l.signIn(_clientId);
    expect(
      spotifyChallenge(verifier!),
      browser.opened.single.queryParameters['code_challenge'],
    );
    expect(verifier, hasLength(64));
  });

  test('ungültige Client-ID: Hinweis, Browser bleibt zu', () async {
    expect(await login.signIn('zu-kurz'), SpotifyLoginError.invalidClientId);
    expect(browser.opened, isEmpty);
    expect(await secrets.clientId(), isNull);
  });

  test('falscher State wird abgelehnt, nichts gespeichert', () async {
    browser.stateOverride = 'fremd';
    expect(await login.signIn(_clientId), SpotifyLoginError.stateMismatch);
    expect(api.methodCalls, isNot(contains('exchangeCode')));
    expect(await secrets.auth(), isNull);
    expect(await secrets.clientId(), isNull);
  });

  test('access_denied und andere Fehler der Rückleitung', () async {
    browser.error = 'access_denied';
    expect(await login.signIn(_clientId), SpotifyLoginError.accessDenied);
    browser.error = 'invalid_client';
    expect(await login.signIn(_clientId), SpotifyLoginError.denied);
    expect(await secrets.auth(), isNull);
  });

  test('ohne Code, abgelehnter Code, kein Browser', () async {
    browser.code = null;
    expect(await login.signIn(_clientId), SpotifyLoginError.noCode);
    browser.code = 'falsch';
    expect(await login.signIn(_clientId), SpotifyLoginError.rejected);
    browser.code = FakeSpotifyApi.validCode;
    browser.failure = SpotifyBrowserFailure.noBrowser;
    expect(await login.signIn(_clientId), SpotifyLoginError.noBrowser);
    expect(await secrets.auth(), isNull);
  });

  test(
    'Browser meldet falschen State: eigener Fehler, nicht „abgebrochen“',
    () async {
      browser.failure = SpotifyBrowserFailure.stateMismatch;
      expect(await login.signIn(_clientId), SpotifyLoginError.stateMismatch);
      browser.failure = SpotifyBrowserFailure.cancelled;
      expect(await login.signIn(_clientId), SpotifyLoginError.cancelled);
      browser.failure = SpotifyBrowserFailure.failed;
      expect(await login.signIn(_clientId), SpotifyLoginError.failed);
      expect(await secrets.auth(), isNull);
    },
  );

  test('Abmelden löscht Token und Client-ID', () async {
    await login.signIn(_clientId);
    await login.signOut();
    expect(await secrets.auth(), isNull);
    expect(await secrets.clientId(), isNull);
  });

  test('SpotifyAuth: toString verbirgt Token, JSON-Rundlauf', () {
    final a = SpotifyAuth(
      accessToken: 'geheim-a',
      refreshToken: 'geheim-r',
      expiresAt: DateTime.utc(2030),
    );
    expect(a.toString(), isNot(contains('geheim')));
    final back = SpotifyAuth.fromJson(a.toJson())!;
    expect(back.accessToken, 'geheim-a');
    expect(back.refreshToken, 'geheim-r');
    expect(back.expiresAt, a.expiresAt);
    expect(SpotifyAuth.fromJson({'accessToken': 'x'}), isNull);
    expect(SpotifyAuth.fromJson('x'), isNull);
  });
}

class _SpyApi implements SpotifyApi {
  _SpyApi(this.inner, this.onVerifier);
  final SpotifyApi inner;
  final void Function(String) onVerifier;

  @override
  Future<SpotifyAuth> exchangeCode({
    required String clientId,
    required String code,
    required String verifier,
    required Uri redirect,
  }) {
    onVerifier(verifier);
    return inner.exchangeCode(
      clientId: clientId,
      code: code,
      verifier: verifier,
      redirect: redirect,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
