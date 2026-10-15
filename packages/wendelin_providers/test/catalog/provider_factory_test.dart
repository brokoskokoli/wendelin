import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/fake_server.dart';
import '../support/sample_conversation.dart';

void main() {
  group('providerTemplates', () {
    test('alle geforderten Vorlagen vorhanden', () {
      expect(providerTemplates.map((t) => t.id), [
        'claude',
        'openai',
        'openrouter',
        'mistral',
        'phala',
        'near',
        'tinfoil',
        'ollama',
        'custom',
      ]);
      for (final t in providerTemplates) {
        if (t.auth == TemplateAuth.apiKey) {
          expect(t.keyPageUrl, startsWith('https://'), reason: t.id);
        }
        expect(t.toString(), contains(t.id));
      }
    });

    test('Datenschutzstufen und Phala-Details', () {
      final phala = providerTemplateById('phala')!;
      expect(phala.baseUrl, 'https://api.redpill.ai/v1');
      expect(phala.privacy, PrivacyLevel.tee);
      expect(phala.options['teeModelsOnly'], isTrue);
      expect(providerTemplateById('ollama')!.privacy, PrivacyLevel.local);
      expect(providerTemplateById('ollama')!.auth, TemplateAuth.none);
      expect(providerTemplateById('mistral')!.privacy, PrivacyLevel.eu);
      expect(providerTemplateById('claude')!.type, ProviderType.anthropic);
      expect(providerTemplateById('gibtsnicht'), isNull);
    });

    test('toProfile', () {
      final p = providerTemplateById('phala')!
          .toProfile(id: 'p1', secretRef: 'phala-key');
      expect(p.name, 'Phala (RedPill)');
      expect(p.baseUrl, 'https://api.redpill.ai/v1');
      expect(p.authMethod, const ApiKeyAuth('phala-key'));
      expect(p.defaultModel, 'z-ai/glm-5.3-flash');
      expect(p.options, {'teeModelsOnly': true, 'attestation': 'phala'});

      final ollama = providerTemplateById('ollama')!
          .toProfile(id: 'o', model: 'llama3.2', secretRef: 'ignoriert');
      expect(ollama.authMethod, const NoAuth());

      final custom = providerTemplateById('custom')!.toProfile(
        id: 'c',
        name: 'Mein Server',
        model: 'm',
        baseUrl: 'https://llm.example/v1',
      );
      expect(custom.authMethod, const NoAuth());
      expect(custom.name, 'Mein Server');
    });

    test('toProfile: fehlende Angaben', () {
      expect(
        () => providerTemplateById('claude')!.toProfile(id: 'x'),
        throwsArgumentError,
      );
      expect(
        () =>
            providerTemplateById('openrouter')!
                .toProfile(id: 'x', secretRef: 'k'),
        throwsArgumentError,
      );
      expect(
        () => providerTemplateById('custom')!.toProfile(id: 'x', model: 'm'),
        throwsArgumentError,
      );
    });
  });

  group('ProviderFactory', () {
    ProviderProfile profile(
      ProviderType type, {
      String? baseUrl,
      PrivacyLevel privacy = PrivacyLevel.standard,
      String model = 'm',
      Map<String, Object?> options = const {},
    }) => ProviderProfile(
      id: 'id',
      name: 'Testprofil',
      type: type,
      baseUrl: baseUrl,
      defaultModel: model,
      privacy: privacy,
      authMethod: const ApiKeyAuth('ref'),
      extraHeaders: const {'x-extra': 'ja'},
      options: options,
    );

    group('Phala-Profil mit Attestierung', () {
      ProviderProfile phala({
        Map<String, Object?>? options,
        String? baseUrl,
        PrivacyLevel privacy = PrivacyLevel.tee,
      }) => profile(
        ProviderType.openaiCompatible,
        baseUrl: baseUrl ?? 'https://api.redpill.ai/v1',
        privacy: privacy,
        options: options ?? {'attestation': 'phala'},
      );
      final wiring = AttestationWiring(
        crypto: FakeAttestationCrypto(),
        logSink: InMemoryAttestationLog(),
        gpuMode: GpuCheckMode.after,
      );

      test('wird zu AttestedProvider mit GPU-Modus und aci_verified', () {
        final p = ProviderFactory.create(
          phala(),
          (_) async => 'k',
          attestation: wiring,
        );
        expect(p, isA<AttestedProvider>());
        final attested = p as AttestedProvider;
        expect(attested.gpuMode, GpuCheckMode.after);
        expect(attested.profileId, 'id');
        final extra = attested.inner.options.extraBody;
        expect((extra['provider']! as Map)['aci_verified'], isTrue);
      });

      test('Option noTools schaltet „ohne Tools“ am AttestedProvider ein', () {
        AttestedProvider build(Map<String, Object?> o) =>
            ProviderFactory.create(
              phala(options: {'attestation': 'phala', ...o}),
              (_) async => 'k',
              attestation: wiring,
            ) as AttestedProvider;
        expect(build({}).noTools, isFalse);
        expect(build({'noTools': true}).noTools, isTrue);
        expect(build({'noTools': true}).caps.tools, isFalse);
      });

      test(
        'ohne pinnedClient: Adapter und Prüfung nutzen PinnedHttpClient',
        () async {
          final connected = <Uri>[];
          final p = ProviderFactory.create(
            phala(),
            (_) async => 'k',
            attestation: AttestationWiring(
              crypto: FakeAttestationCrypto(),
              tlsConnect: (url) async {
                connected.add(url);
                throw const SocketException('stub');
              },
            ),
          ) as AttestedProvider;
          // Content client: must open its connection through the pinned
          // client (a plain http.Client would never call the hook).
          await expectLater(p.inner.listModels(), throwsA(anything));
          expect(connected.map((u) => u.host), ['api.redpill.ai']);
          // Attestation client likewise.
          await p.verifier.attest().then((_) {}, onError: (_) {});
          expect(connected, hasLength(2));
        },
      );

      test('Host mit Punkt am Ende oder Großbuchstaben wird geprüft', () {
        for (final url in [
          'https://api.redpill.ai./v1',
          'https://API.RedPill.ai/v1',
        ]) {
          final p = phala(baseUrl: url, options: const {});
          expect(needsAttestation(p), isTrue, reason: url);
          expect(
            () => ProviderFactory.create(p, (_) async => 'k'),
            throwsArgumentError,
            reason: 'nie ungeprüft bauen',
          );
          expect(
            ProviderFactory.create(p, (_) async => 'k', attestation: wiring),
            isA<AttestedProvider>(),
          );
        }
      });

      test('effectivePrivacy: TEE nur für geprüfte Profile', () {
        expect(effectivePrivacy(phala()), PrivacyLevel.tee);
        final unchecked = phala(
          baseUrl: 'https://llm.example/v1',
          options: const {},
        );
        expect(effectivePrivacy(unchecked), PrivacyLevel.standard);
        expect(
          effectivePrivacy(phala(privacy: PrivacyLevel.local)),
          PrivacyLevel.local,
        );
      });

      test('älteres Profil auf dem RedPill-Host ohne Option wird geprüft', () {
        final p = ProviderFactory.create(
          phala(options: const {'teeModelsOnly': true}),
          (_) async => 'k',
          attestation: wiring,
        );
        expect(p, isA<AttestedProvider>());
      });

      test(
        'ohne Wiring fail-closed; anderer Host ohne Option: normaler Adapter',
        () {
          expect(
            () => ProviderFactory.create(phala(), (_) async => 'k'),
            throwsArgumentError,
            reason: 'nie ungeprüft bauen',
          );
          expect(
            needsAttestation(phala(privacy: PrivacyLevel.standard)),
            isTrue,
            reason: 'an die Option gebunden, nicht an die Datenschutzstufe',
          );
          expect(
            ProviderFactory.create(
              phala(baseUrl: 'https://llm.example/v1', options: const {}),
              (_) async => 'k',
              attestation: wiring,
            ),
            isA<OpenAiChatAdapter>(),
          );
          expect(
            needsAttestation(
              profile(
                ProviderType.openaiCompatible,
                baseUrl: 'https://llm.example/v1',
                privacy: PrivacyLevel.tee,
              ),
            ),
            isFalse,
            reason: 'TEE-Stufe allein heißt nicht geprüft',
          );
        },
      );
    });

    test('Anthropic-Profil → AnthropicMessagesAdapter mit Optionen', () async {
      final server = FakeServer([
        FakeResponse.sse(fixture('anthropic/text.sse')),
      ]);
      final reads = <String>[];
      final p = ProviderFactory.create(
        profile(
          ProviderType.anthropic,
          options: {'enableServerWebSearch': true},
        ),
        (ref) async {
          reads.add(ref);
          return 'key-from-store';
        },
        client: server.client,
      );
      expect(p, isA<AnthropicMessagesAdapter>());
      expect(reads, isEmpty, reason: 'Secret erst beim Request lesen');
      await p.chat(sampleRequest()).toList();
      expect(reads, ['ref']);
      final r = server.requests.single;
      expect(r.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(r.headers['x-api-key'], 'key-from-store');
      expect(r.headers['x-extra'], 'ja');
      expect(
        (r.json['tools']! as List).first,
        containsPair('name', 'web_search'),
      );
    });

    test('Anthropic mit eigener Base-URL', () async {
      final server = FakeServer([
        FakeResponse.sse(fixture('anthropic/text.sse')),
      ]);
      await ProviderFactory.create(
        profile(ProviderType.anthropic, baseUrl: 'https://proxy.example'),
        (_) async => 'k',
        client: server.client,
      ).chat(sampleRequest()).toList();
      expect(server.requests.single.url.host, 'proxy.example');
    });

    test(
      'OpenAI-kompatibel → OpenAiChatAdapter mit Label, TEE, Vision',
      () async {
        final server = FakeServer([const FakeResponse.json(401, '{}')]);
        final p = ProviderFactory.create(
          profile(
            ProviderType.openaiCompatible,
            baseUrl: 'https://llm.example/v1',
            privacy: PrivacyLevel.tee,
            model: 'gpt-4.1-nano',
            options: {'teeModelsOnly': true},
          ),
          (_) async => 'k',
          client: server.client,
        );
        expect(p, isA<OpenAiChatAdapter>());
        expect(p.caps.tee, isFalse, reason: 'nicht geprüft: kein TEE');
        expect(p.caps.vision, isTrue);
        final events = await p.chat(sampleRequest()).toList();
        expect(
          (events.single as ErrorEvent).error.message,
          startsWith('Testprofil:'),
        );
        expect(server.requests.single.headers['Authorization'], 'Bearer k');
      },
    );

    test('unbekanntes Modell: keine Vision, kein TEE', () {
      final p = ProviderFactory.create(
        profile(ProviderType.openaiCompatible, baseUrl: 'http://x.local/v1'),
        (_) async => null,
      );
      expect(p.caps.vision, isFalse);
      expect(p.caps.tee, isFalse);
    });

    test('Fehler: OpenAI ohne Base-URL, Fake-Profil', () {
      expect(
        () => ProviderFactory.create(
          profile(ProviderType.openaiCompatible),
          (_) async => null,
        ),
        throwsArgumentError,
      );
      expect(
        () => ProviderFactory.create(
          profile(ProviderType.fake),
          (_) async => null,
        ),
        throwsArgumentError,
      );
    });
  });
}
