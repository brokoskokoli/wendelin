// Gerätetest (WP128): Nachfrage bei Ausfall.
//
// Die echte App auf dem Emulator, ohne Netz: Das Standardprofil („Erster“)
// fällt aus (Netzwerkfehler, auch beim einen Wiederholversuch), die App
// fragt „Mit Zweiter nochmal?“, ein Tipp darauf, und das zweite Profil
// antwortet. Danach prüft der Test den Audit-Eintrag der Antwort und dass
// das erste Profil nicht öfter als nötig gefragt wurde. Im zweiten Lauf
// sagt der Nutzer „Nein“: Fehlermeldung wie bisher, das zweite Profil
// bekommt nichts.
//
// Läuft über `tool/e2e_android.sh` (nur Emulator).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/e2e.dart';

ProviderProfile _profile(String id, String name) => ProviderProfile(
  id: id,
  name: name,
  type: ProviderType.anthropic,
  defaultModel: '$id-modell',
  privacy: PrivacyLevel.standard,
  authMethod: ApiKeyAuth('provider.$id.apiKey'),
);

Future<(E2eApp, Map<String, FakeLlmProvider>)> _start(
  WidgetTester tester,
) async {
  const down = NetworkException('weg');
  final llm = {
    'erster': FakeLlmProvider([
      ScriptedTurn.error(down),
      ScriptedTurn.error(down),
    ]),
    'zweiter': FakeLlmProvider([ScriptedTurn.text('Zweiter antwortet.')]),
  };
  final app = E2eApp(
    extraOverrides: [
      llmProviderFactoryProvider.overrideWithValue((p, _) => llm[p.id]!),
    ],
  );
  final profiles = app.storage.providerProfiles;
  await profiles.save(_profile('erster', 'Erster'));
  await profiles.save(_profile('zweiter', 'Zweiter'));
  await profiles.setDefault('erster');
  await app.pump(tester);
  return (app, llm);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Ausfall → „Mit Zweiter nochmal?“ → Tipp → Zweiter antwortet', (
    tester,
  ) async {
    final (app, llm) = await _start(tester);
    await send(tester, 'Wie spät ist es?');
    await pumpUntil(tester, find.text('Mit Zweiter nochmal?'));
    // Das Sheet fährt noch hoch: erst abwarten, sonst trifft der Tipp nicht.
    await tester.pump(const Duration(seconds: 1)); // Sheet-Animation
    // Vor dem Tipp geht nichts an den zweiten Anbieter.
    expect(llm['zweiter']!.requests, isEmpty);
    final yes = find.text('Mit Zweiter nochmal?').last; // Titel + Schaltfläche
    await tester.ensureVisible(yes);
    await tester.tap(yes);
    await pumpUntil(tester, find.textContaining('Zweiter antwortet.'));
    await waitIdle(tester);
    expect(llm['erster']!.requests, hasLength(2));
    expect(llm['zweiter']!.requests, hasLength(1));
    final audit = await app.storage.audit.query();
    expect(
      audit.where(
        (e) =>
            e.payload['type'] == 'retryOffer' && e.payload['approved'] == true,
      ),
      hasLength(1),
    );
    expect(
      audit.where(
        (e) =>
            e.kind == AuditKind.escalation &&
            e.payload['reason'] == 'providerFailed',
      ),
      hasLength(1),
    );
  });

  testWidgets('Ausfall → „Nein“ → Fehlermeldung, Zweiter bekommt nichts', (
    tester,
  ) async {
    final (_, llm) = await _start(tester);
    await send(tester, 'Wie spät ist es?');
    await pumpUntil(tester, find.text('Mit Zweiter nochmal?'));
    await tester.pump(const Duration(seconds: 1)); // Sheet-Animation
    await tester.tap(find.text('Nein').last);
    await waitIdle(tester);
    expect(llm['zweiter']!.requests, isEmpty);
    expect(find.textContaining('Zweiter antwortet.'), findsNothing);
  });
}
