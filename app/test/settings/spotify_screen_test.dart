import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/spotify.dart';
import 'package:wendelin/ui/settings/spotify_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../support/test_env.dart';
import 'integrations_screen_test.dart';

const _clientId = '0123456789abcdef0123456789abcdef';

/// A stored login whose refresh token the fake accepts.
Future<void> loginSpotify(TestEnv env) async {
  await env.secrets.write('spotify.client_id', _clientId);
  await env.secrets.write(
    'spotify.session',
    jsonEncode(
      SpotifyAuth(
        accessToken: 'alt',
        refreshToken: 'refresh-1',
        expiresAt: DateTime.utc(2099),
      ).toJson(),
    ),
  );
}

void main() {
  testWidgets('„Login fehlt – Einrichten“ öffnet die Spotify-Seite mit '
      'Anleitung und Redirect-Adresse; falsche Client-ID speichert nichts, '
      'richtige meldet an', (tester) async {
    final env = TestEnv(enabled: const {'spotify'});
    await pumpIntegrations(tester, env);
    final tileSpotify = tileWidget(tester, 'Spotify');
    expect(tileSpotify.status, IntegrationStatus.setupRequired);
    expect(tileSpotify.detail, 'Login fehlt');
    await tester.tap(
      find.descendant(
        of: tile('Spotify'),
        matching: find.widgetWithText(OutlinedButton, 'Einrichten'),
      ),
    );
    await settle(tester);
    expect(find.byType(SpotifyScreen), findsOneWidget);
    expect(find.textContaining('developer.spotify.com'), findsOneWidget);
    expect(find.textContaining('app.wendelin://oauth/spotify'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('spotifyClientId')),
      'zu-kurz',
    );
    await tester.tap(find.text('Bei Spotify anmelden'));
    await settle(tester);
    expect(find.byKey(const ValueKey('spotifyError')), findsOneWidget);
    expect(env.spotifyBrowser.opened, isEmpty);
    expect(await env.secrets.listKeys(), isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('spotifyClientId')),
      _clientId,
    );
    await tester.tap(find.text('Bei Spotify anmelden'));
    await settle(tester);
    expect(env.spotifyBrowser.opened.single.host, 'accounts.spotify.com');
    expect(await env.secrets.listKeys(), {
      'spotify.client_id',
      'spotify.session',
    });
    expect(find.textContaining('Angemeldet'), findsWidgets);

    await tester.tap(find.byTooltip('Zurück'));
    await settle(tester);
    expect(tileWidget(tester, 'Spotify').status, IntegrationStatus.active);
  });

  testWidgets('abgelehnte Anmeldung zeigt den Grund und speichert nichts', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'spotify'});
    env.spotifyBrowser.error = 'access_denied';
    await pumpIntegrations(tester, env);
    await tester.tap(
      find.descendant(
        of: tile('Spotify'),
        matching: find.widgetWithText(OutlinedButton, 'Einrichten'),
      ),
    );
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('spotifyClientId')),
      _clientId,
    );
    await tester.tap(find.text('Bei Spotify anmelden'));
    await settle(tester);
    expect(find.textContaining('nicht erlaubt'), findsOneWidget);
    expect(await env.secrets.listKeys(), isEmpty);
  });

  testWidgets('Abmelden löscht Client-ID und Tokens', (tester) async {
    final env = TestEnv(enabled: const {'spotify'});
    await loginSpotify(env);
    await pumpIntegrations(tester, env);
    expect(tileWidget(tester, 'Spotify').status, IntegrationStatus.active);
    await tester.tap(find.text('Spotify'));
    await settle(tester);
    await tester.tap(find.text('Spotify-Konto'));
    await settle(tester);
    await tester.tap(find.text('Abmelden'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Abmelden'));
    await settle(tester);
    expect(await env.secrets.listKeys(), isEmpty);
    expect(find.byKey(const ValueKey('spotifyClientId')), findsOneWidget);
  });

  testWidgets('Fehlerzustand mit Grund und „Erneut versuchen“ auf der Kachel', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'spotify'});
    await loginSpotify(env);
    final c = await pumpIntegrations(tester, env);
    final integration = spotifyIntegrationOf(c.read(integrationsProvider))!;
    env.spotify
      ..expireTokens()
      ..revokeRefresh();
    expect(
      await tester.runAsync(integration.reconnect),
      contains('neu anmelden'),
    );
    await settle(tester);
    final failed = tileWidget(tester, 'Spotify');
    expect(failed.status, IntegrationStatus.error);
    expect(failed.detail, contains('Anmeldung abgelaufen'));
    expect(failed.detail, endsWith('pausiert'));
    expect(failed.actionLabel, 'Erneut versuchen');
    // Abgelaufene Anmeldung: Tokens sind gelöscht, Einrichtung nötig.
    expect(await env.secrets.read('spotify.session'), isNull);
  });
}
