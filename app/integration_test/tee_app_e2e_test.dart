// Gerätetest (WP52): Phala-Profil mit Fixture-Transport (Debug-Überschreibung der Provider-
// Factory) in der echten App auf dem Emulator. Die Attestierung läuft mit den Probe-Daten aus
// WP43 und einer Prüf-Attrappe für Quote und Ed25519 (Fixture-Signaturen sind nach dem Umbau
// der Hashes nicht mehr gültig); alles andere (Stufen, Quittungsbindung, Sperre, Protokoll,
// Anzeige) ist die echte App. Kein Netz.
//
// Läuft über `tool/e2e_android.sh` (nur Emulator).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/attestation_providers.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/e2e.dart';
import 'support/tee_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<(E2eApp, FixtureGateway, ProviderContainer)> start(
    WidgetTester tester,
  ) async {
    final gateway = FixtureGateway();
    final app = E2eApp(
      extraOverrides: [
        llmProviderFactoryProvider.overrideWith(
          (ref) => (profile, secrets) {
            final provider = AttestedProvider(
              inner: OpenAiChatAdapter(
                baseUrl: Uri.parse(profile.baseUrl!),
                credentials: Credentials.apiKey(
                  'e2e-key',
                  style: ApiKeyStyle.bearer,
                ),
                defaultModel: profile.defaultModel,
                client: gateway.client,
                options: const OpenAiOptions(
                  extraBody: {
                    'provider': {'aci_verified': true},
                  },
                ),
                capabilities: const ProviderCapabilities(
                  tools: true,
                  streaming: true,
                  tee: true,
                ),
              ),
              verifier: PhalaVerifier(
                crypto: FakeAttestationCrypto(ed25519Result: true),
                baseUrl: Uri.parse(profile.baseUrl!),
                profileId: profile.id,
                client: gateway.client,
                settings: HttpSettings(clock: FixedClock(probeNow)),
                nonceSource: () => probeNonce,
              ),
              profileId: profile.id,
              logSink: ref.read(attestationLogWriterProvider),
              settings: HttpSettings(clock: FixedClock(probeNow)),
              retryDelay: Duration.zero,
            );
            ref.read(attestationHubProvider).register(profile.id, provider);
            return provider;
          },
        ),
      ],
    );
    await app.storage.providerProfiles.save(
      ProviderProfile(
        id: 'phala',
        name: 'Phala · GLM klein',
        type: ProviderType.openaiCompatible,
        baseUrl: 'https://gateway.test/v1',
        defaultModel: 'z-ai/glm-5.3-flash',
        privacy: PrivacyLevel.tee,
        authMethod: const ApiKeyAuth('provider.phala.apiKey'),
        options: const {'attestation': 'phala', 'teeModelsOnly': true},
      ),
    );
    await app.storage.providerProfiles.setDefault('phala');
    await app.secrets.write('provider.phala.apiKey', 'e2e-key');
    final c = await app.pump(tester);
    return (app, gateway, c);
  }

  testWidgets('Text-Anfrage an das Phala-Profil: grünes Schild, Protokoll mit '
      'allen Stufen', (tester) async {
    final (app, gateway, _) = await start(tester);
    await send(tester, 'Wie wird das Meer morgen?');
    await pumpUntil(tester, find.textContaining('Ruhig: 0,4 m Welle.'));
    await pumpUntil(tester, find.text('geprüft'));
    expect(gateway.chats, 1);
    expect(find.byType(StatusCard), findsNothing);

    final records = await app.storage.attestations.latest();
    final receipt = records.firstWhere(
      (r) => r.kind == AttestationRecordKind.receipt,
    );
    expect(receipt.status, AttestationStatus.green);
    expect(receipt.receiptId, 'rcpt-fixture');
    expect(receipt.stepId, isNotNull, reason: 'am Gesprächsschritt');
    expect(
      receipt.stages.map((s) => s.stage),
      containsAll(['receipt.signature', 'receipt.request', 'receipt.response']),
    );
    final session = records.firstWhere(
      (r) => r.kind == AttestationRecordKind.session,
    );
    expect(
      session.stages.map((s) => s.stage),
      containsAll(['quote', 'nonce', 'keyset.digest', 'freshness']),
    );
    expect(session.stages.every((s) => s.result != 'fail'), isTrue);
  });

  testWidgets('Manipulierte Quittung: rotes Schild mit Warnkarte, Anbieter '
      'gesperrt, nichts Weiteres gesendet', (tester) async {
    final (app, gateway, c) = await start(tester);
    gateway.tamper = (r) {
      for (final e in (r['event_log']! as List).cast<Map<String, Object?>>()) {
        if (e['type'] == 'response.returned') {
          e['body_hash'] = 'sha256:${'0' * 64}';
        }
      }
    };
    await send(tester, 'Wie wird das Meer morgen?');
    await pumpUntil(tester, find.text('Neu prüfen'));
    expect(find.text('Prüfung fehlgeschlagen'), findsWidgets);
    expect(c.read(attestationHubProvider).isLocked('phala'), isTrue);

    await send(tester, 'Noch eine Frage');
    await waitIdle(tester);
    expect(gateway.chats, 1, reason: 'gesperrt: nichts mehr gesendet');
    final red = (await app.storage.attestations.latest()).where(
      (r) => r.status == AttestationStatus.red,
    );
    expect(red, isNotEmpty);
    // ignore: avoid_print
    print(
      'Rote Stufen: ${red.first.stages.where((s) => s.result == 'fail').map((s) => s.stage)}',
    );
  });
}
