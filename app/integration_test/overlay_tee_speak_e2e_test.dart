// Gerätetest WP81: Overlay mit TEE-Profil (aufgezeichnetes Gateway, Rust-Prüfmodul).
// Die Quittung wird um 4 s verzögert. (1) Die gesprochene Antwort muss vor der
// grünen Quittung beginnen; (2) bei roter (manipulierter) Quittung bricht die
// Ausgabe ab, der Warnhinweis wird gesprochen. Prüfung der Reihenfolge durch den
// Aufrufer per logcat (`Wendelin/voice answer-complete`, `speak`,
// `Wendelin/attest: receipt …`).
//
//   WENDELIN_MODELS=~/wendelin-models \
//     tool/e2e_android.sh integration_test/overlay_tee_speak_e2e_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/bootstrap/run_app.dart';
import 'package:wendelin/debug/device_test_overrides.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/attestation_providers.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/main.dart' as app show openAppStorage;
import 'package:wendelin/platform/attest/attest_backend.dart';
import 'package:wendelin/platform/attest/collateral_cache.dart';
import 'package:wendelin/platform/attest/pcs_collateral_client.dart';
import 'package:wendelin/platform/attest/rust_attestation_crypto.dart';
import 'package:wendelin/platform/secure_secret_store.dart';
import 'package:wendelin/ui/overlay/assistant_overlay.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/testing.dart' show FakeTextToSpeech;

import 'support/receipt_substitute.dart';
import 'support/tee_gateway.dart';
import 'support/voice_e2e.dart';

@pragma('vm:entry-point')
Future<void> assistantMain() async {
  voiceLogEngine = 'overlay';
  WidgetsFlutterBinding.ensureInitialized();
  final (storage, startup) = await app.openAppStorage();
  final dir = await e2eDirectory();
  final spec = jsonDecode(
    File('${dir.path}/overlay.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final gateway = FixtureGateway()
    ..receiptDelay = Duration(milliseconds: spec['receiptDelayMs']! as int);
  if (spec['tamper'] == true) {
    gateway.tamper = (r) {
      for (final e in (r['event_log']! as List).cast<Map<String, Object?>>()) {
        if (e['type'] == 'response.returned') {
          e['body_hash'] = 'sha256:${'0' * 64}';
        }
      }
    };
  }
  final backend = await FrbAttestBackend.init();
  final tmp = Directory.systemTemp.createTempSync('tee-overlay-e2e');
  await runWendelinApp(
    storage,
    startup,
    const AssistantOverlayApp(),
    extra: [
      ...await deviceTestOverrides(),
      systemTtsProvider.overrideWithValue(
        FakeTextToSpeech(utteranceDuration: const Duration(seconds: 3)),
      ),
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
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<List<AttestationRecord>> receipts() async {
    final (storage, _) = await app.openAppStorage();
    try {
      return [
        for (final r in await storage.attestations.latest())
          if (r.kind == AttestationRecordKind.receipt) r,
      ];
    } finally {
      await storage.close();
    }
  }

  Future<void> run(Directory e2e, {required bool tamper}) async {
    File('${e2e.path}/overlay.json').writeAsStringSync(
      jsonEncode({
        'audio': 'de-02.wav',
        'receiptDelayMs': 4000,
        'tamper': tamper,
      }),
    );
    final before = (await receipts()).length;
    await askHost('assist');
    final end = DateTime.now().add(const Duration(seconds: 120));
    while ((await receipts()).length <= before) {
      if (DateTime.now().isAfter(end)) fail('Keine Quittung im Protokoll');
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    // ignore: avoid_print
    print(
      'WP81 ${tamper ? 'rot' : 'gruen'}: '
      '${(await receipts()).first.status}',
    );
    await Future<void>.delayed(const Duration(seconds: 8));
    await askHost('back');
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  testWidgets(
    'Overlay TEE: Antwort vor Quittung gesprochen; rote Quittung meldet',
    (tester) async {
      await waitForDeviceFiles();
      final e2e = await e2eDirectory();
      addTearDown(() {
        for (final f in ['overlay.json', 'de-02.wav']) {
          final file = File('${e2e.path}/$f');
          if (file.existsSync()) file.deleteSync();
        }
      });
      final setup = WendelinStorage(driftDatabase(name: 'wendelin'));
      await setup.settings.set(AppSettings.onboardingDone, true);
      await setup.settings.set(
        voiceSettingsKey,
        const VoiceSettings(sttModel: 'whisper-base'),
      );
      await setup.providerProfiles.save(
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
      await setup.providerProfiles.setDefault('phala');
      await setup.close();
      await SecureSecretStore().write('provider.phala.apiKey', 'e2e-key');
      File(await fixtureWav('de-02')).copySync('${e2e.path}/de-02.wav');

      await run(e2e, tamper: false);
      expect((await receipts()).first.status, AttestationStatus.green);
      await run(e2e, tamper: true);
      expect((await receipts()).first.status, AttestationStatus.red);
      // Conversation mode: the red receipt must also end the conversation
      // (`conv-exit reason=error`, checked by the caller in logcat).
      final conv = WendelinStorage(driftDatabase(name: 'wendelin'));
      await conv.settings.set(
        voiceSettingsKey,
        const VoiceSettings(sttModel: 'whisper-base', conversationMode: true),
      );
      await conv.close();
      await run(e2e, tamper: true);
      expect((await receipts()).first.status, AttestationStatus.red);
      await askHost('unrole');
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
