// Gerätetest (WP52): Phala-Profil in der echten App auf dem Emulator. Der Provider kommt aus
// der echten Factory-Verdrahtung (`llmProviderFactoryProvider`, AttestedProvider, PhalaVerifier)
// mit dem Rust-Prüfmodul (`RustAttestationCrypto`): die TDX-Quote wird echt gegen das
// aufgezeichnete Intel-Kollateral geprüft. Ersetzt sind nur der Transport (aufgezeichnetes
// Gateway, Uhr und Nonce der Aufzeichnung) und die Ed25519-Prüfung der Quittung (die
// Fixture-Quittungen werden mit den echten Hashes neu gebaut, ihre Signatur kann nicht mehr
// stimmen). Alles andere (Stufen, Quittungsbindung, Sperre, Protokoll, Anzeige) ist die echte
// App. Kein Netz.
//
// Läuft über `tool/e2e_android.sh` (nur Emulator).

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/attestation_providers.dart';
import 'package:wendelin/platform/attest/attest_backend.dart';
import 'package:wendelin/platform/attest/collateral_cache.dart';
import 'package:wendelin/platform/attest/pcs_collateral_client.dart';
import 'package:wendelin/platform/attest/rust_attestation_crypto.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/e2e.dart';
import 'support/receipt_substitute.dart';
import 'support/tee_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<(E2eApp, FixtureGateway, ProviderContainer)> start(
    WidgetTester tester,
  ) async {
    final gateway = FixtureGateway();
    final backend = await FrbAttestBackend.init();
    final tmp = Directory.systemTemp.createTempSync('tee-app-e2e');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final app = E2eApp(
      extraOverrides: [
        // The production factory builds the provider; only the transport
        // (recorded gateway), the clock/nonce of the recording and the
        // collateral source (recorded Intel PCS answers) are replaced.
        attestationTransportProvider.overrideWithValue(
          AttestationTransport(
            client: gateway.client,
            pinnedClient: gateway.pinned,
            settings: HttpSettings(clock: FixedClock(probeNow)),
            nonceSource: () => probeNonce,
          ),
        ),
        attestationCryptoProvider.overrideWith(
          (ref) async => ReceiptSignatureSubstitute(
            RustAttestationCrypto(
              backend: backend,
              pcs: PcsCollateralClient(
                client: pcsFixtureClient(),
                backend: backend,
              ),
              cache: CollateralCache(dir: tmp, now: () => probeNow),
              clock: () => probeNow,
            ),
            gateway.e2ee,
          ),
        ),
      ],
    );
    await app.storage.providerProfiles.save(
      ProviderProfile(
        id: 'phala',
        name: 'Phala · GLM klein',
        type: ProviderType.openaiCompatible,
        baseUrl: 'https://api.redpill.ai/v1',
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
    await pumpUntil(tester, find.textContaining(l10n(tester).attSummaryGreen));
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
    // End-to-end encryption (WP62): the gateway decrypted the real Rust
    // cipher text, and the key came from the attested keyset.
    expect(session.stages.map((s) => s.stage), contains('e2ee.key'));
    final messages = gateway.lastPlainBody!['messages']! as List<Object?>;
    expect(
      messages.map((m) => (m! as Map)['content']),
      contains('Wie wird das Meer morgen?'),
    );
  });

  testWidgets('Gateway antwortet unverschlüsselt: Antwort wird nie angezeigt', (
    tester,
  ) async {
    final (_, gateway, _) = await start(tester);
    gateway.plainAnswer = true;
    await send(tester, 'Wie wird das Meer morgen?');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(gateway.chats, 1);
    expect(find.textContaining('Ruhig: 0,4 m Welle.'), findsNothing);
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
    await pumpUntil(tester, find.text(l10n(tester).attLogRecheck));
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
