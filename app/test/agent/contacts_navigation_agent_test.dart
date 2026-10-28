// WP164 A: „Navigiere zu <Kontakt>“ läuft über contacts__find(fields:
// [address]) und maps__navigate(destination: <Adresse>), mit den echten
// Werkzeugen und dem Adressbuch-Fake.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../screens/main_screen_test.dart' show pumpApp, pumpUntil, send;
import '../support/test_env.dart';

const _home = 'Musterstraße 1, 12345 Musterstadt';

void main() {
  testWidgets(
    'Navigiere zu Anna Meier: Adresse aus dem Adressbuch, dann Maps',
    (tester) async {
      final provider = FakeLlmProvider([
        ScriptedTurn.toolCalls([
          call(
            'c1',
            'contacts__find',
            jsonEncode({
              'query': 'Anna Meier',
              'fields': ['address'],
            }),
          ),
        ]),
        ScriptedTurn.toolCalls([
          call('c2', 'maps__navigate', jsonEncode({'destination': _home})),
        ]),
        ScriptedTurn.text('Navigation gestartet.'),
      ]);
      final env = TestEnv(
        providerConfig: scripted(provider),
        startup: const StartupSettings(
          enabledIntegrations: {'contacts', 'maps'},
        ),
      );
      env.contacts.contacts = const [
        ContactEntry(
          name: 'Anna Meier',
          phones: [ContactPhone('+49 170 1234567', label: 'Mobil')],
          addresses: [ContactAddress(_home, label: 'Privat')],
          birthday: '1985-03-14',
        ),
      ];
      await pumpApp(tester, env);
      await send(tester, 'Navigiere zu Anna Meier');
      await pumpUntil(tester, find.text('Navigation gestartet.'));

      // Das Adressbuch wurde nur nach der Adresse gefragt.
      expect(env.contacts.requested, [
        {ContactField.address},
      ]);
      // Das Modell sah die Adresse, aber weder Nummer noch Geburtstag.
      final seen = jsonEncode([
        for (final m in provider.requests.last.messages)
          for (final b in m.content) b.toJson(),
      ]);
      expect(seen, contains('Musterstraße 1'));
      expect(seen, isNot(contains('1234567')));
      expect(seen, isNot(contains('1985')));
      // Genau diese Adresse ging an Google Maps.
      final launch = env.mapsLauncher.launched.single;
      expect(launch.package, googleMapsPackage);
      expect(
        Uri.decodeComponent(launch.uri.toString()),
        startsWith('google.navigation:q=$_home'),
      );
    },
  );
}
