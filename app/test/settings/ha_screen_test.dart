import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/hint_term_providers.dart';
import 'package:wendelin/di/home_assistant.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/ui/settings/ha_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../support/test_env.dart';
import 'integrations_screen_test.dart';

/// Token of the fake instance (canary: must stay in the store).
const haToken = 'kanarien-token';

Future<void> openHa(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: tile('Home Assistant (direkt)'),
      matching: find.widgetWithText(OutlinedButton, 'Einrichten'),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('Einrichten: öffentliche http-Adresse und falsches Token '
      'speichern nichts, richtige Angaben verbinden', (tester) async {
    final env = TestEnv(enabled: const {'ha'});
    final c = await pumpIntegrations(tester, env);
    final ha = tileWidget(tester, 'Home Assistant (direkt)');
    expect(ha.status, IntegrationStatus.setupRequired);
    expect(ha.detail, startsWith('Verbindung fehlt'));
    await openHa(tester);
    expect(find.byType(HaScreen), findsOneWidget);

    Future<void> connect(String address, String token) async {
      await tester.enterText(find.byKey(const ValueKey('haAddress')), address);
      await tester.enterText(find.byKey(const ValueKey('haToken')), token);
      await tester.tap(find.text('Verbinden'));
      await settle(tester);
    }

    await connect('http://example.com:8123', haToken);
    expect(find.byKey(const ValueKey('haError')), findsOneWidget);
    expect(find.textContaining('nur im Heimnetz'), findsWidgets);
    expect(await env.secrets.listKeys(), isEmpty);

    env.ha.failNext(
      'check',
      const PortException(
        PortErrorKind.permissionDenied,
        'Home Assistant hat das Token abgelehnt.',
      ),
    );
    await connect('192.168.1.20:8123', 'falsch');
    expect(
      find.text('Home Assistant hat das Token abgelehnt.'),
      findsOneWidget,
    );
    expect(await env.secrets.listKeys(), isEmpty);

    await connect('192.168.1.20:8123', haToken);
    expect(find.text('Verbunden'), findsOneWidget);
    expect(find.text('http://192.168.1.20:8123'), findsOneWidget);
    expect(await env.secrets.listKeys(), {'ha.url', 'ha.token'});
    expect(await env.secrets.read('ha.token'), haToken);
    expect(find.text('Küche Deckenlicht'), findsOneWidget);
    expect(find.text('0 Geräte freigegeben'), findsOneWidget);
    // Weder Token noch Gerätenamen stehen im Klartext auf dem Bildschirm.
    expect(find.text(haToken), findsNothing);

    // Gerät freigeben: nur dieses geht ans Modell.
    await tester.tap(find.byKey(const ValueKey('haEntity_light.kitchen')));
    await settle(tester);
    expect(find.text('1 Gerät freigegeben'), findsOneWidget);
    final store = c.read(haStoreProvider);
    expect((await store.load()).map((e) => e.entityId), ['light.kitchen']);
    expect(c.read(toolRegistryProvider).status('ha'), IntegrationStatus.active);
    expect(
      (await store.load()).single,
      const HaEntity(
        entityId: 'light.kitchen',
        name: 'Küche Deckenlicht',
        area: 'Küche',
      ),
    );

    // Schalter: „Immer bestätigen“ erscheint erst nach der Freigabe und
    // bleibt gespeichert, auch wenn danach andere Geräte geändert werden.
    const confirmKey = ValueKey('haConfirm_switch.coffee');
    expect(find.byKey(confirmKey), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('haEntity_switch.coffee')),
    );
    await tester.tap(find.byKey(const ValueKey('haEntity_switch.coffee')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(confirmKey));
    await tester.tap(find.byKey(confirmKey));
    await settle(tester);
    Future<bool?> confirmed(String id) async => (await store.load())
        .where((e) => e.entityId == id)
        .map((e) => e.alwaysConfirm)
        .firstOrNull;
    expect(await confirmed('switch.coffee'), isTrue);
    expect(await confirmed('light.kitchen'), isFalse);
    await tester.tap(find.byKey(const ValueKey('haEntity_light.kitchen')));
    await settle(tester);
    expect(await confirmed('switch.coffee'), isTrue);

    // Trennen löscht alles.
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await settle(tester);
    await tester.tap(find.text('Trennen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Trennen'));
    await settle(tester);
    expect(await env.secrets.listKeys(), isEmpty);
    expect(find.byKey(const ValueKey('haAddress')), findsOneWidget);
  });

  testWidgets('Freigabe ändern und Trennen: Hinweisbegriffe folgen', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'ha'});
    final c = await pumpIntegrations(tester, env);
    await openHa(tester);
    await tester.enterText(
      find.byKey(const ValueKey('haAddress')),
      '192.168.1.20:8123',
    );
    await tester.enterText(find.byKey(const ValueKey('haToken')), haToken);
    await tester.tap(find.text('Verbinden'));
    await settle(tester);
    c.listen(hintTermsProvider, (_, _) {});
    expect(await c.read(hintTermsProvider.future), isNot(contains('Küche')));

    await tester.tap(find.byKey(const ValueKey('haEntity_light.kitchen')));
    await settle(tester);
    expect(await c.read(hintTermsProvider.future), contains('Küche'));

    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await settle(tester);
    await tester.tap(find.text('Trennen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Trennen'));
    await settle(tester);
    expect(await c.read(hintTermsProvider.future), isNot(contains('Küche')));
  });

  testWidgets('Suche im WLAN füllt die Adresse; ohne Treffer Hinweis', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'ha'});
    await pumpIntegrations(tester, env);
    await openHa(tester);
    await tester.tap(find.text('Im WLAN suchen'));
    await settle(tester);
    expect(find.textContaining('Nichts gefunden'), findsOneWidget);

    env.haDiscovery.servers = const [
      HaServer(name: 'Zuhause', url: 'http://192.168.1.20:8123'),
    ];
    await tester.tap(find.text('Im WLAN suchen'));
    await settle(tester);
    await tester.tap(find.text('Zuhause'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('haAddress')))
          .controller!
          .text,
      'http://192.168.1.20:8123',
    );
  });

  testWidgets('Fehlerzustand: „Erneut versuchen“ prüft die Verbindung', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'ha'});
    await env.secrets.write('ha.url', 'http://192.168.1.20:8123');
    await env.secrets.write('ha.token', haToken);
    await env.secrets.write(
      'ha.entities',
      '[{"id":"light.kitchen","name":"Küche Deckenlicht","area":"Küche"}]',
    );
    final c = await pumpIntegrations(tester, env);
    expect(
      tileWidget(tester, 'Home Assistant (direkt)').status,
      IntegrationStatus.active,
    );
    final integration = haIntegrationOf(c.read(integrationsProvider))!;
    env.ha.failNext(
      'check',
      const PortException(
        PortErrorKind.permissionDenied,
        'Home Assistant hat das Token abgelehnt.',
      ),
    );
    expect(
      await tester.runAsync(integration.reconnect),
      contains('Token abgelehnt'),
    );
    await settle(tester);
    final failed = tileWidget(tester, 'Home Assistant (direkt)');
    expect(failed.status, IntegrationStatus.error);
    expect(failed.detail, contains('Token abgelehnt'));
    expect(failed.actionLabel, 'Erneut versuchen');

    await tester.tap(find.text('Home Assistant (direkt)'));
    await settle(tester);
    await tester.tap(find.text('Adresse, Token und Geräte'));
    await settle(tester);
    expect(find.text('Fehler – nicht erreichbar'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Erneut versuchen'));
    await settle(tester);
    expect(find.text('Home Assistant ist erreichbar.'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(c.read(toolRegistryProvider).status('ha'), IntegrationStatus.active);
  });
}
