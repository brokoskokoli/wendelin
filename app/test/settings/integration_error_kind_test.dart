import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/google_tasks.dart';
import 'package:wendelin/di/integrations/integration_spec.dart'
    show pausedError;
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/todoist.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/l10n/gen/app_localizations_en.dart';
import 'package:wendelin/l10n/gen/app_localizations_fr.dart';
import 'package:wendelin/ui/settings/integrations_screen.dart';
import 'package:wendelin/ui/settings/reconnect_text.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support/test_env.dart';
import 'bring_screen_test.dart' show loginBring;
import 'integrations_screen_test.dart';
import 'spotify_screen_test.dart' show loginSpotify;

/// Integration under test: id, tile title, display name, seeding of the
/// "logged in" state and the row that opens the account page (if any).
typedef _Case = (
  String id,
  String tile,
  String name,
  Future<void> Function(TestEnv) seed,
  String? row,
);

final _cases = <_Case>[
  ('bring', 'Bring! Einkaufsliste', 'Bring!', loginBring, 'Bring!-Konto'),
  ('spotify', 'Spotify', 'Spotify', loginSpotify, 'Spotify-Konto'),
  (
    'todoist',
    'Todoist',
    'Todoist',
    (env) => env.secrets.write('todoist.token', 'x'),
    'Todoist-Konto',
  ),
  (
    'gtasks',
    'Google Tasks',
    'Google Tasks',
    (env) async {
      await env.secrets.write('gtasks.client_id', 'id');
      await env.secrets.write('gtasks.client_secret', 'secret');
      await env.secrets.write('gtasks.refresh_token', 'r');
    },
    'Google-Konto',
  ),
  (
    'ha',
    'Home Assistant (direkt)',
    'Home Assistant',
    (env) async {
      await env.secrets.write('ha.url', 'http://192.168.1.20:8123');
      await env.secrets.write('ha.token', 'x');
      await env.secrets.write('ha.entities', '[]');
    },
    'Adresse, Token und Geräte',
  ),
];

/// Expected German tile text per kind (suffix after the service name).
const _expected = <PortErrorKind?, String>{
  PortErrorKind.permissionDenied: 'Zugang abgelehnt oder abgelaufen · pausiert',
  PortErrorKind.unavailable: 'nicht erreichbar · pausiert',
  PortErrorKind.failed: 'unerwartete Antwort · pausiert',
  null: 'Zugang abgelehnt oder unerwartete Antwort · pausiert',
};

void main() {
  for (final (id, tileName, name, seed, row) in _cases) {
    testWidgets('$id: Kachel und Seite nennen die Fehlerart', (tester) async {
      final env = TestEnv(enabled: {id});
      await seed(env);
      final c = await pumpIntegrations(tester, env);
      final registry = c.read(toolRegistryProvider);
      for (final MapEntry(key: kind, value: text) in _expected.entries) {
        registry.reportError(id, pausedError, kind: kind);
        await settle(tester);
        final failed = tileWidget(tester, tileName);
        expect(failed.status, IntegrationStatus.error, reason: '$kind');
        expect(failed.detail, contains(text), reason: '$id $kind');
        expect(failed.detail, contains(name));
        // Distinct per kind: the other kinds' wording is not shown.
        for (final other in _expected.entries.where((e) => e.key != kind)) {
          if (other.value == text || text.contains(other.value)) continue;
          expect(failed.detail, isNot(contains(other.value)));
        }
        expect(failed.actionLabel, 'Erneut versuchen');

        await tester.tap(find.text(tileName));
        await settle(tester);
        if (row != null) {
          await tester.tap(find.text(row));
          await settle(tester);
        }
        expect(find.textContaining(text), findsOneWidget, reason: '$id Seite');
        expect(find.text('Erneut versuchen'), findsOneWidget);
        await tester.tap(find.byTooltip('Zurück'));
        await settle(tester);
        if (row != null) {
          await tester.tap(find.byTooltip('Zurück'));
          await settle(tester);
        }
        expect(find.byType(IntegrationsScreen), findsOneWidget);
      }
      // clearError nimmt Fehler und Art zurück.
      registry.reportError(id, pausedError, kind: PortErrorKind.failed);
      registry.clearError(id);
      expect(registry.info(id).errorKind, isNull);
      expect(registry.info(id).error, isNull);
    });
  }

  testWidgets('Todoist: abgelehntes Token meldet die Art bis zur Registry', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'todoist'});
    await env.secrets.write('todoist.token', 'falsch');
    final c = await pumpIntegrations(tester, env);
    final integration = todoistIntegrationOf(c.read(integrationsProvider))!;
    final failure = await tester.runAsync(integration.reconnect);
    expect(failure!.kind, PortErrorKind.permissionDenied);
    final info = c.read(toolRegistryProvider).info('todoist');
    expect(info.status, IntegrationStatus.error);
    expect(info.errorKind, PortErrorKind.permissionDenied);
  });

  testWidgets('Google Tasks: widerrufener Login meldet die Art', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'gtasks'});
    await _cases.firstWhere((x) => x.$1 == 'gtasks').$4(env);
    final c = await pumpIntegrations(tester, env);
    final integration = googleTasksIntegrationOf(c.read(integrationsProvider))!;
    final failure = await tester.runAsync(integration.reconnect);
    expect(failure, isNotNull);
    final info = c.read(toolRegistryProvider).info('gtasks');
    expect(info.status, IntegrationStatus.error);
    expect(info.errorKind, failure!.kind);
    expect(info.errorKind, PortErrorKind.permissionDenied);
  });

  test('Texte je Art in de, en und fr; Bring!-Anmeldung bleibt', () {
    final de = AppLocalizationsDe();
    final en = AppLocalizationsEn();
    final fr = AppLocalizationsFr();
    for (final (kind, d, e, f) in [
      (
        PortErrorKind.permissionDenied,
        'abgelehnt oder abgelaufen',
        'refused or expired',
        'refusé ou expiré',
      ),
      (
        PortErrorKind.unavailable,
        'nicht erreichbar',
        'not reachable',
        'injoignable',
      ),
      (
        PortErrorKind.failed,
        'unerwartete Antwort',
        'unexpected answer',
        'réponse inattendue',
      ),
      (
        PortErrorKind.rejected,
        'unerwartete Antwort · pausiert',
        'unexpected answer · paused',
        'réponse inattendue · en pause',
      ),
    ]) {
      final reject = kind == PortErrorKind.rejected;
      // Unbekannte Art: bisheriger generischer Pausentext.
      expect(
        integrationErrorText(de, 'todoist', pausedError, kind),
        reject ? de.integrationsPausedError('Todoist') : contains(d),
      );
      expect(
        integrationErrorText(en, 'todoist', pausedError, kind),
        reject ? en.integrationsPausedError('Todoist') : contains(e),
      );
      expect(
        integrationErrorText(fr, 'todoist', pausedError, kind),
        reject ? fr.integrationsPausedError('Todoist') : contains(f),
      );
    }
    expect(
      integrationErrorText(en, 'bring', 'reauth', PortErrorKind.failed),
      en.bringReauthError,
    );
    expect(integrationErrorText(en, 'ha', 'Freitext'), 'Freitext');
  });
}
