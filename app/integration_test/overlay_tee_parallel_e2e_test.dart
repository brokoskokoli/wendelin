// Gerätetest WP81c: parallele Runde im Overlay mit TEE-Profil. Modell 400 ms,
// Quittung 1,5 s. Runde 1: Schreibwerkzeug (Undo), Runde 2 (parallel zur
// Quittung von Runde 1): Text; rot zusätzlich SMS (external). Grün: erster
// Ton vor `receipt green`. Rot: Ausgabe abgebrochen, Hinweis, SMS nie
// ausgeführt, Text nicht im Verlauf, Undo genau 1x. Die Zeitpunkte liest der
// Aufrufer aus logcat (`E2E81C ...`, `Wendelin/voice: speak`,
// `Wendelin/attest: receipt`).
//
//   WENDELIN_MODELS=~/wendelin-models \
//     tool/e2e_android.sh integration_test/overlay_tee_parallel_e2e_test.dart

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
import 'package:wendelin/di/integration_providers.dart';
import 'package:wendelin/di/routing.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/main.dart' as app show openAppStorage;
import 'package:wendelin/platform/attest/attest_backend.dart';
import 'package:wendelin/platform/attest/collateral_cache.dart';
import 'package:wendelin/platform/attest/pcs_collateral_client.dart';
import 'package:wendelin/platform/attest/rust_attestation_crypto.dart';
import 'package:wendelin/platform/secure_secret_store.dart';
import 'package:wendelin/ui/overlay/assistant_overlay.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_core/testing.dart' show FakeIntegration, FakeTool;
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/testing.dart' show FakeTextToSpeech;
import 'package:wendelin_voice/wendelin_voice.dart';

import 'support/receipt_substitute.dart';
import 'support/tee_gateway.dart';
import 'support/voice_e2e.dart';

String _sse(String text, [Map<String, Object?>? call]) {
  final delta = <String, Object?>{
    'role': 'assistant',
    if (text.isNotEmpty) 'content': text,
    if (call != null)
      'tool_calls': [
        {
          'index': 0,
          'id': 'call_${call['name']}',
          'type': 'function',
          'function': {'name': call['name'], 'arguments': '{}'},
        },
      ],
  };
  String chunk(Object? d, String? finish) =>
      'data: ${jsonEncode({
        'id': 'c1',
        'object': 'chat.completion.chunk',
        'choices': [
          {'index': 0, 'delta': d, 'finish_reason': finish},
        ],
      })}\n\n';
  return '${chunk(delta, null)}${chunk(const <String, Object?>{}, call == null ? 'stop' : 'tool_calls')}'
      'data: [DONE]\n\n';
}

final class _LoggingTts implements TextToSpeech {
  _LoggingTts(this._inner);

  final TextToSpeech _inner;

  @override
  Future<bool> get isAvailable => _inner.isAvailable;
  @override
  Future<List<TtsVoice>> voices() => _inner.voices();
  @override
  TtsState get state => _inner.state;
  @override
  Stream<TtsState> get states => _inner.states;
  @override
  Future<void> speak(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  }) {
    _log('tts speak "$text"');
    return _inner.speak(text, voice: voice, language: language, rate: rate);
  }

  @override
  Future<void> stop() {
    _log('tts stop');
    return _inner.stop();
  }
}

void _log(String s) {
  // ignore: avoid_print
  print('E2E81C $s');
}

@pragma('vm:entry-point')
Future<void> assistantMain() async {
  voiceLogEngine = 'overlay';
  WidgetsFlutterBinding.ensureInitialized();
  final (storage, startup) = await app.openAppStorage();
  final dir = await e2eDirectory();
  final spec = jsonDecode(
    File('${dir.path}/overlay.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final red = spec['tamper'] == true;
  final gateway = FixtureGateway()
    ..receiptDelay = const Duration(milliseconds: 1500)
    ..chatDelay = const Duration(milliseconds: 400)
    ..onEvent = _log
    ..chatScript = [
      _sse('', {'name': 'calendar__write_note'}),
      red
          ? _sse(
              'Ich schicke die Nachricht jetzt ab. Einen kleinen Moment noch.',
              {'name': 'calendar__send_sms'},
            )
          : _sse('Die Notiz ist angelegt und alles erledigt.'),
      _sse('Erledigt.'),
    ];
  if (red) {
    gateway.tamper = (r) {
      for (final e in (r['event_log']! as List).cast<Map<String, Object?>>()) {
        if (e['type'] == 'response.returned') {
          e['body_hash'] = 'sha256:${'0' * 64}';
        }
      }
    };
  }
  final note = FakeTool(
    name: 'calendar__write_note',
    risk: RiskLevel.write,
    handler: (args, ctx) {
      _log('tool write_note exec');
      return ToolOutcome(
        content: [const TextBlock('ok')],
        undo: UndoAction(
          label: 'Rückgängig',
          run: () async => _log('tool write_note UNDO'),
        ),
      );
    },
  );
  final sms = FakeTool(
    name: 'calendar__send_sms',
    risk: RiskLevel.external,
    handler: (args, ctx) {
      _log('tool send_sms EXEC');
      return ToolOutcome.text('gesendet');
    },
  );
  final backend = await FrbAttestBackend.init();
  final tmp = Directory.systemTemp.createTempSync('tee-overlay-e2e');
  await runWendelinApp(
    storage,
    startup,
    const AssistantOverlayApp(),
    extra: [
      ...await deviceTestOverrides(),
      integrationsProvider.overrideWithValue({
        'calendar': FakeIntegration(id: 'calendar', tools: [note, sms]),
      }),
      systemTtsProvider.overrideWithValue(
        _LoggingTts(
          FakeTextToSpeech(utteranceDuration: const Duration(seconds: 3)),
        ),
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
    _log('--- scenario ${tamper ? 'red' : 'green'}');
    File(
      '${e2e.path}/overlay.json',
    ).writeAsStringSync(jsonEncode({'audio': 'de-02.wav', 'tamper': tamper}));
    final before = (await receipts()).length;
    await askHost('assist');
    final end = DateTime.now().add(const Duration(seconds: 120));
    final want = tamper ? 1 : 2;
    while ((await receipts()).length < before + want) {
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
      // Restzustand (WP104): wie overlay_tee_speak aufräumen, sonst sieht die
      // nächste Testdatei Profil, Schlüssel, Regeln und Hinweis.
      addTearDown(() async {
        final reset = WendelinStorage(driftDatabase(name: 'wendelin'));
        try {
          await reset.providerProfiles.delete('phala');
          await reset.settings.remove(voiceSettingsKey);
          await reset.settings.remove(AppSettings.setupWizardDone);
          await reset.settings.remove(
            AppSettings.integrationEnabled('calendar'),
          );
          await reset.settings.remove(RoutingSettings.rules);
          await reset.settings.remove(RoutingSettings.privateRuleNotice);
        } finally {
          await reset.close();
        }
        await SecureSecretStore().delete('provider.phala.apiKey');
      });
      final setup = WendelinStorage(driftDatabase(name: 'wendelin'));
      await setup.settings.set(AppSettings.setupWizardDone, true);
      await setup.settings.set(
        AppSettings.integrationEnabled('calendar'),
        true,
      );
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
      final check = WendelinStorage(driftDatabase(name: 'wendelin'));
      var shown = false;
      for (final se in await check.conversations.sessions()) {
        for (final m in await check.conversations.messages(se.id)) {
          if ('${m.message}'.contains('Nachricht jetzt ab')) shown = true;
        }
      }
      await check.close();
      _log('history contains discarded text: $shown');
      expect(shown, isFalse);
      await askHost('unrole');
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
