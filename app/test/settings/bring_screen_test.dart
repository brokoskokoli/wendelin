import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/bring.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/bring_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../support/test_env.dart';
import 'integrations_screen_test.dart';

/// Password of the fake Bring! account (canary: must stay in the store).
const bringPassword = 'kanarien-passwort';

Future<void> loginBring(TestEnv env) async {
  await env.secrets.write('bring.email', env.bring.email);
  await env.secrets.write('bring.password', bringPassword);
}

void main() {
  testWidgets('„Login fehlt – Einrichten“ öffnet die Bring!-Seite; Login '
      'mit falschem Passwort speichert nichts, mit richtigem wird aktiv', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'bring'});
    await pumpIntegrations(tester, env);
    final bring = tileWidget(tester, 'Bring! Einkaufsliste');
    expect(bring.status, IntegrationStatus.setupRequired);
    expect(bring.detail, 'Login fehlt');
    await tester.tap(
      find.descendant(
        of: tile('Bring! Einkaufsliste'),
        matching: find.widgetWithText(OutlinedButton, 'Einrichten'),
      ),
    );
    await settle(tester);
    expect(find.byType(BringScreen), findsOneWidget);
    expect(find.textContaining('Inoffizielle Schnittstelle'), findsOneWidget);
    expect(find.textContaining('Installiert'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('bringEmail')),
      env.bring.email,
    );
    await tester.enterText(
      find.byKey(const ValueKey('bringPassword')),
      'falsch',
    );
    await tester.tap(find.text('Anmelden'));
    await settle(tester);
    expect(find.byKey(const ValueKey('bringError')), findsOneWidget);
    expect(await env.secrets.listKeys(), isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('bringPassword')),
      bringPassword,
    );
    await tester.tap(find.text('Anmelden'));
    await settle(tester);
    expect(find.text('Angemeldet'), findsOneWidget);
    expect(find.text(env.bring.email), findsOneWidget);
    expect(find.text('Aktiv'), findsOneWidget);
    expect(await env.secrets.listKeys(), {
      'bring.email',
      'bring.password',
      'bring.session',
    });

    await tester.tap(find.byTooltip('Zurück'));
    await settle(tester);
    expect(
      tileWidget(tester, 'Bring! Einkaufsliste').status,
      IntegrationStatus.active,
    );
  });

  testWidgets('Abmelden löscht Zugangsdaten und Tokens', (tester) async {
    final env = TestEnv(enabled: const {'bring'});
    await loginBring(env);
    final c = await pumpIntegrations(tester, env);
    expect(
      tileWidget(tester, 'Bring! Einkaufsliste').status,
      IntegrationStatus.active,
    );
    // Eine Sitzung entsteht beim ersten Aufruf.
    final integration = bringIntegrationOf(c.read(integrationsProvider))!;
    expect(await tester.runAsync(integration.reconnect), isNull);
    expect(await env.secrets.read('bring.session'), isNotNull);

    await tester.tap(find.text('Bring! Einkaufsliste'));
    await settle(tester);
    await tester.tap(find.text('Bring!-Konto'));
    await settle(tester);
    await tester.tap(find.text('Abmelden'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Abmelden'));
    await settle(tester);
    expect(await env.secrets.listKeys(), isEmpty);
    expect(find.byKey(const ValueKey('bringEmail')), findsOneWidget);
    expect(
      c.read(toolRegistryProvider).status('bring'),
      IntegrationStatus.setupRequired,
    );
  });

  testWidgets('Fehlerzustand mit Grund, „Erneut versuchen“ auf der Kachel '
      'und auf der Seite', (tester) async {
    final env = TestEnv(enabled: const {'bring'});
    await loginBring(env);
    final c = await pumpIntegrations(tester, env);
    final integration = bringIntegrationOf(c.read(integrationsProvider))!;
    env.bring.failNext(
      'login',
      const PortException(PortErrorKind.failed, 'Bring!: unerwartete Antwort'),
    );
    expect(
      await tester.runAsync(integration.reconnect),
      contains('unerwartete Antwort'),
    );
    await settle(tester);
    final failed = tileWidget(tester, 'Bring! Einkaufsliste');
    expect(failed.status, IntegrationStatus.error);
    expect(failed.detail, contains('unerwartete Antwort'));
    expect(failed.detail, endsWith('pausiert'));
    expect(failed.actionLabel, 'Erneut versuchen');

    // Seite: Fehler mit Grund und eigener Knopf.
    await tester.tap(find.text('Bring! Einkaufsliste'));
    await settle(tester);
    await tester.tap(find.text('Bring!-Konto'));
    await settle(tester);
    expect(
      find.text('Fehler – Schnittstelle nicht erreichbar'),
      findsOneWidget,
    );
    expect(find.textContaining('unerwartete Antwort'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await settle(tester);
    await tester.tap(find.byTooltip('Zurück'));
    await settle(tester);

    await tester.tap(
      find.descendant(
        of: tile('Bring! Einkaufsliste'),
        matching: find.widgetWithText(OutlinedButton, 'Erneut versuchen'),
      ),
    );
    await settle(tester);
    expect(find.textContaining('wieder erreichbar'), findsOneWidget);
    expect(
      tileWidget(tester, 'Bring! Einkaufsliste').status,
      IntegrationStatus.active,
    );
  });

  testWidgets('Bring!-App fehlt: Hinweis auf der Kachel und der Seite', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'bring'});
    env.apps.uninstall(BringAppFallback.androidPackage);
    await loginBring(env);
    await pumpIntegrations(tester, env);
    expect(
      tileWidget(tester, 'Bring! Einkaufsliste').detail,
      contains('Bring!-App fehlt'),
    );
    await tester.tap(find.text('Bring! Einkaufsliste'));
    await settle(tester);
    await tester.tap(find.text('Bring!-Konto'));
    await settle(tester);
    expect(find.text('Nicht installiert'), findsOneWidget);
    expect(find.byType(WSwitch), findsNothing);
  });
}
