// Gerätetest (WP76d): Tinfoil-Profil in der echten App auf dem Emulator. Der Provider kommt aus
// der echten Factory-Verdrahtung (`llmProviderFactoryProvider`, AttestedProvider, TinfoilVerifier,
// TinfoilEhbpChannel) mit dem Rust-Prüfmodul: der aufgezeichnete öffentliche SNP-Report des
// Routers (Genoa) wird mit dem aufgezeichneten VCEK und der AMD-Kette echt geprüft, das
// Sigstore-Bundle des Releases v0.0.158 echt gegen den Sigstore-Vertrauensanker, HPKE-Schlüssel
// und TLS-Pin kommen allein aus `report_data`, die EHBP-Verschlüsselung ist der echte Rust-Code.
// Ersetzt sind nur der Transport (aufgezeichnete Router-/AMD-/GitHub-Antworten, Router mit
// eigenem HPKE-Schlüssel), das Zertifikat der Verbindung (Ersatz mit dem Pin des Reports) und die
// Uhr der Prüfung. Kein Netz.
//
// Läuft über `tool/e2e_android.sh` (nur Emulator).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/attestation_providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/l10n/l10n.dart';
import 'package:wendelin/platform/attest/attest_backend.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/e2e.dart';
import 'support/tee_gateway.dart' show FixturePinnedClient;
import 'support/tinfoil_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<(E2eApp, TinfoilFixtureGateway, TinfoilBackend, ProviderContainer)>
  start(
    WidgetTester tester, {
    ReleaseFloor? floor,
    bool wrongPin = false,
  }) async {
    final gateway = TinfoilFixtureGateway();
    final backend = TinfoilBackend(
      await FrbAttestBackend.init(),
      gateway.service,
    )..wrongPin = wrongPin;
    final app = E2eApp(
      startup: const StartupSettings(enabledIntegrations: {'memory'}),
      extraOverrides: [
        attestBackendProvider.overrideWith((ref) async => backend),
        attestationTransportProvider.overrideWithValue(
          AttestationTransport(
            client: gateway.client,
            pinnedClient: (gate, {required enforce}) =>
                FixturePinnedClient(gateway.client, gate, enforce: enforce),
            settings: HttpSettings(clock: FixedClock(tinfoilNow)),
          ),
        ),
      ],
    );
    await app.storage.providerProfiles.save(
      ProviderProfile(
        id: 'tinfoil',
        name: 'Tinfoil (TEE)',
        type: ProviderType.openaiCompatible,
        baseUrl: tinfoilBaseUrl,
        defaultModel: tinfoilModelId,
        privacy: PrivacyLevel.tee,
        authMethod: const ApiKeyAuth('provider.tinfoil.apiKey'),
        options: const {
          'attestation': 'tinfoil',
          'modelType': 'chat',
          'toolsOnly': true,
        },
      ),
    );
    await app.storage.providerProfiles.setDefault('tinfoil');
    await app.secrets.write('provider.tinfoil.apiKey', 'e2e-key');
    if (floor != null) {
      await app.storage.settings.set(
        AppSettings.releaseFloor('tinfoil'),
        floor.toJson(),
      );
    }
    final c = await app.pump(tester);
    return (app, gateway, backend, c);
  }

  Future<List<AttestationRecord>> redRecords(
    WidgetTester tester,
    E2eApp app,
  ) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      final red = (await app.storage.attestations.latest()).where(
        (r) => r.status == AttestationStatus.red,
      );
      if (red.isNotEmpty) return red.toList();
    }
    return const [];
  }

  testWidgets('Text-Anfrage mit Werkzeugzug an das Tinfoil-Profil: grünes '
      'Schild, Protokoll mit allen Stufen, nichts im Klartext', (tester) async {
    final (app, gateway, _, _) = await start(tester);
    await send(tester, 'Wie wird das Meer morgen?');
    await pumpUntil(tester, find.textContaining(tinfoilAnswer));
    // Sprachneutral: die Emulator-Sprache entscheidet (en: „verified, …“).
    final l = tester.element(find.byType(Scaffold).first).l10n;
    await pumpUntil(tester, find.textContaining(l.attSummaryGreen));
    expect(find.byType(StatusCard), findsNothing);
    // Zug 1 (Werkzeugaufruf) und Zug 2 (mit Werkzeugergebnis), beide EHBP.
    expect(gateway.chats, 2);
    expect(
      (gateway.plainBodies.first['messages']! as List<Object?>).map(
        (m) => (m! as Map)['content'],
      ),
      contains('Wie wird das Meer morgen?'),
    );
    expect(
      (gateway.plainBodies.last['messages']! as List<Object?>).map(
        (m) => (m! as Map)['role'],
      ),
      contains('tool'),
    );
    for (final wire in gateway.wires) {
      expect(wire, isNot(contains('Meer morgen')));
      expect(wire, isNot(contains('memory__')));
      expect(wire, isNot(contains('messages')));
    }

    final records = await app.storage.attestations.latest();
    final session = records.firstWhere(
      (r) => r.kind == AttestationRecordKind.session,
    );
    expect(
      session.stages.map((s) => s.stage),
      containsAll([
        'snp.report',
        'snp.chain',
        'snp.policy',
        'tls.spki',
        'bind.hpke',
        'sigstore.release',
        'measurement',
        'release.floor',
        'e2ee.key',
      ]),
    );
    expect(session.stages.every((s) => s.result != 'fail'), isTrue);
    expect(records.any((r) => r.status == AttestationStatus.red), isFalse);
    // AMD und GitHub direkt, nie der Router.
    expect(
      gateway.external.map((u) => u.host).toSet(),
      containsAll(['kdsintf.amd.com', 'api.github.com']),
    );
  });

  testWidgets('Release-Rückschritt (K59): rotes Schild, keine Anfrage', (
    tester,
  ) async {
    final (app, gateway, _, c) = await start(
      tester,
      floor: ReleaseFloor(
        version: ReleaseVersion.tryParse('v0.0.159')!,
        integratedTime: 1792000000,
      ),
    );
    await send(tester, 'Wie wird das Meer morgen?');
    final red = await redRecords(tester, app);
    expect(red, isNotEmpty);
    expect(
      red
          .expand((r) => r.stages)
          .where((s) => s.result == 'fail')
          .map((s) => s.stage),
      contains('release.floor'),
    );
    expect(gateway.chats, 0, reason: 'fail-closed: nichts gesendet');
    expect(find.textContaining(tinfoilAnswer), findsNothing);
    expect(c.read(attestationHubProvider).isLocked('tinfoil'), isTrue);
  });

  testWidgets('Falscher TLS-Pin: rotes Schild, keine Anfrage', (tester) async {
    final (app, gateway, _, _) = await start(tester, wrongPin: true);
    await send(tester, 'Wie wird das Meer morgen?');
    final red = await redRecords(tester, app);
    expect(red, isNotEmpty);
    expect(gateway.chats, 0, reason: 'fail-closed: nichts gesendet');
    expect(find.textContaining(tinfoilAnswer), findsNothing);
  });
}
