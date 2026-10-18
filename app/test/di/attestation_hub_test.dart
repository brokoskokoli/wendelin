import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/attestation_hub.dart';
import 'package:wendelin/di/attestation_providers.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin_agent/testing.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/tee_app_support.dart';
import '../support/test_env.dart';

ProviderProfile _phala({Map<String, Object?> options = const {}}) =>
    ProviderProfile(
      id: 'phala',
      name: 'Phala (RedPill)',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://api.redpill.ai/v1',
      defaultModel: 'z-ai/glm-5.3-flash',
      privacy: PrivacyLevel.tee,
      authMethod: const ApiKeyAuth('provider.phala.apiKey'),
      options: {'attestation': 'phala', ...options},
    );

void main() {
  group('AttestationHub', () {
    late AttestationHub hub;
    late RecordingNotifier notifier;
    late ScriptedVerifier verifier;
    late AttestedProvider provider;

    setUp(() {
      notifier = RecordingNotifier();
      verifier = ScriptedVerifier();
      provider = scriptedTee(verifier: verifier, gateway: ScriptedGateway());
      hub = AttestationHub(notifier: notifier, nameOf: (_) => 'Phala');
    });

    tearDown(() => hub.dispose());

    test('Modus gilt für registrierte und später registrierte Provider', () {
      hub.gpuMode = GpuCheckMode.after;
      hub.register('phala', provider);
      expect(provider.gpuMode, GpuCheckMode.after);
      hub.gpuMode = GpuCheckMode.before;
      expect(provider.gpuMode, GpuCheckMode.before);
    });

    test('neu aufgebauter Provider desselben Profils übernimmt die geprüfte '
        'Sitzung (WP77)', () async {
      hub.register('phala', provider);
      await hub.warmUp('phala');
      expect(verifier.attests, 1);
      // Profile list or rules changed: the configuration builds anew.
      final verifier2 = ScriptedVerifier();
      final rebuilt = scriptedTee(
        verifier: verifier2,
        gateway: ScriptedGateway(),
      );
      hub.register('phala', rebuilt);
      expect(rebuilt.session, isNotNull);
      await hub.warmUp('phala');
      expect(verifier2.attests, 0, reason: 'keine zweite Sitzungsprüfung');
      expect(identical(hub.provider('phala'), rebuilt), isTrue);
    });

    test('gesperrter Vorgänger: der neue Provider prüft selbst', () async {
      verifier.sessionStages = const [
        StageResult.fail(AttestationStage.quote, 'x'),
      ];
      hub.register('phala', provider);
      await hub.warmUp('phala');
      expect(hub.isLocked('phala'), isTrue);
      final verifier2 = ScriptedVerifier();
      final rebuilt = scriptedTee(
        verifier: verifier2,
        gateway: ScriptedGateway(),
      );
      hub.register('phala', rebuilt);
      expect(rebuilt.session, isNull);
      await hub.warmUp('phala');
      expect(verifier2.attests, 1);
    });

    test('Ergebnisse tragen die Profil-Id', () async {
      hub.register('phala', provider);
      final seen = hub.reports.first;
      await provider.reattest();
      expect((await seen).profileId, 'phala');
    });

    test('warmUp: attestiert vorab, entsperrt nicht, wirft nicht', () async {
      hub.register('phala', provider);
      await hub.warmUp('phala');
      expect(verifier.attests, 1);
      await hub.warmUp('phala');
      expect(verifier.attests, 1, reason: 'gültige Sitzung');
      await hub.warmUp('unbekannt'); // kein Absturz
    });

    for (final (mode, shown) in [
      (GpuCheckMode.before, 0),
      (GpuCheckMode.after, 1),
    ]) {
      test(
        'GPU-Fehler im Modus ${mode.name}: $shown Benachrichtigung(en)',
        () async {
          final gpu = FakeGpuAttestationVerifier(
            const GpuAttestationResult(GpuVerdict.failed),
          );
          final p = scriptedTee(
            verifier: verifier,
            gateway: ScriptedGateway(),
            gpu: gpu,
          );
          hub
            ..gpuMode = mode
            ..register('phala', p);
          await p
              .chat(
                ChatRequest(
                  model: 'm',
                  maxTokens: 10,
                  messages: [Message.user('x')],
                ),
              )
              .toList();
          await pumpEventQueue(times: 50);
          expect(notifier.shown, hasLength(shown));
          if (shown > 0) {
            expect(notifier.shown.single.$2, contains('Phala'));
          }
        },
      );
    }
  });

  group('warmUpAttestation', () {
    late ScriptedVerifier verifier;
    late AttestationHub hub;

    ProviderConfig config(String id) => ProviderConfig(
      primary: ProviderTarget(
        profileId: id,
        modelId: 'm',
        provider: FakeLlmProvider(const []),
        privacy: PrivacyLevel.tee,
      ),
    );

    setUp(() {
      verifier = ScriptedVerifier();
      hub = AttestationHub(notifier: RecordingNotifier())
        ..register(
          'phala',
          scriptedTee(verifier: verifier, gateway: ScriptedGateway()),
        );
    });

    test('online und TEE-Standardprofil: attestiert im Hintergrund', () async {
      await warmUpAttestation(
        config: Future.value(config('phala')),
        network: FixedNetworkStatus(),
        hub: hub,
      );
      expect(verifier.attests, 1);
    });

    test(
      'offline, anderes Standardprofil oder keine Konfiguration: nichts',
      () async {
        await warmUpAttestation(
          config: Future.value(config('phala')),
          network: FixedNetworkStatus(NetworkState.offline),
          hub: hub,
        );
        await warmUpAttestation(
          config: Future.value(config('lokal')),
          network: FixedNetworkStatus(),
          hub: hub,
        );
        await warmUpAttestation(
          config: Future.value(),
          network: FixedNetworkStatus(),
          hub: hub,
        );
        await warmUpAttestation(
          config: Future.error(StateError('x')),
          network: FixedNetworkStatus(),
          hub: hub,
        );
        expect(verifier.attests, 0);
      },
    );
  });

  group('Provider-Factory der App', () {
    test(
      'Nonce-Quelle der Verdrahtung ist im Standard null (zufällig)',
      () async {
        final c = TestEnv(storedProfiles: true).container();
        addTearDown(c.dispose);
        await awaitCheckModule(c.read(attestationCryptoProvider.future));
        final wiring = Provider(attestationWiringOf);
        expect(c.read(wiring)?.nonceSource, isNull);
        final fixed = TestEnv(
          extraOverrides: [
            attestationTransportProvider.overrideWithValue(
              AttestationTransport(
                client: ScriptedGateway().client,
                settings: const HttpSettings(),
                nonceSource: () => Uint8List(32),
              ),
            ),
          ],
        ).container();
        addTearDown(fixed.dispose);
        await awaitCheckModule(fixed.read(attestationCryptoProvider.future));
        expect(fixed.read(wiring)?.nonceSource, isNotNull);
      },
    );

    test('TEE-Profil wird AttestedProvider und im Hub registriert', () async {
      final env = TestEnv(storedProfiles: true);
      final c = env.container();
      addTearDown(c.dispose);
      await awaitCheckModule(c.read(attestationCryptoProvider.future));
      final create = c.read(llmProviderFactoryProvider);
      final p = create(_phala(), env.secrets.read);
      expect(p, isA<AttestedProvider>());
      expect(c.read(attestationHubProvider).provider('phala'), same(p));
    });

    test(
      'WP81: gleiches Profil gibt dieselbe Instanz zurück (kein Neuaufbau)',
      () async {
        final env = TestEnv(storedProfiles: true);
        final c = env.container();
        addTearDown(c.dispose);
        await awaitCheckModule(c.read(attestationCryptoProvider.future));
        final create = c.read(llmProviderFactoryProvider);
        final first = create(_phala(), env.secrets.read);
        final again = create(_phala(), env.secrets.read);
        expect(again, same(first));
        expect(c.read(attestationHubProvider).provider('phala'), same(first));
      },
    );

    test('WP81: geändertes Profil baut neu auf', () async {
      final env = TestEnv(storedProfiles: true);
      final c = env.container();
      addTearDown(c.dispose);
      await awaitCheckModule(c.read(attestationCryptoProvider.future));
      final create = c.read(llmProviderFactoryProvider);
      final first = create(_phala(), env.secrets.read);
      final changed = create(
        _phala(options: const {'noTools': true}),
        env.secrets.read,
      );
      expect(changed, isNot(same(first)));
      expect(c.read(attestationHubProvider).provider('phala'), same(changed));
    });

    test('GPU-Modus aus den Einstellungen', () async {
      final env = TestEnv(
        storedProfiles: true,
        startup: const StartupSettings(gpuCheck: GpuCheckMode.before),
      );
      final c = env.container();
      addTearDown(c.dispose);
      await awaitCheckModule(c.read(attestationCryptoProvider.future));
      final p = c.read(llmProviderFactoryProvider)(
        _phala(),
        env.secrets.read,
      ) as AttestedProvider;
      expect(p.gpuMode, GpuCheckMode.before);
    });

    test('ohne geladenes Prüfmodul: kein ungeprüfter Provider', () async {
      final env = TestEnv(
        storedProfiles: true,
        attestationCryptoError: StateError('keine Bibliothek'),
      );
      final c = env.container();
      addTearDown(c.dispose);
      await awaitCheckModule(c.read(attestationCryptoProvider.future));
      expect(
        () => c.read(llmProviderFactoryProvider)(_phala(), env.secrets.read),
        throwsArgumentError,
      );
    });

    test('Pin wird je Profil in den Einstellungen gespeichert', () async {
      final env = TestEnv();
      final c = env.container();
      addTearDown(c.dispose);
      final store = c.read(attestationPinStoreProvider);
      expect(await store.load('phala'), isNull);
      final pin = AttestationPin(
        keysetDigest: 'sha256:k',
        composeHash: 'c',
        repoCommit: 'abc',
        pinnedAt: testNow,
      );
      await store.save('phala', pin);
      expect((await store.load('phala'))?.keysetDigest, 'sha256:k');
      await env.storage.settings.set(AppSettings.attestationPin('phala'), {
        'kaputt': true,
      });
      expect(
        await store.load('phala'),
        isNull,
        reason: 'beschädigt = kein Pin',
      );
    });
  });
}
