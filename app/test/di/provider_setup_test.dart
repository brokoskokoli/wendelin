import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/maintenance.dart';
import 'package:wendelin/di/profiles.dart';
import 'package:wendelin/di/provider_setup.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/test_env.dart';

const _key = 'testschluessel-0123456789abcdef-GEHEIM';

/// Fake adapter factory that behaves like a real server: the key must be
/// stored, `listModels` needs no model, `test()` fails with 404 for a model
/// the server does not know (like Ollama or OpenRouter).
final class RecordingFactory {
  RecordingFactory({this.ok = true, this.models = const [], this.listError});

  /// Thrown by `listModels` (server without a model list).
  ProviderException? listError;

  /// Whether the key is accepted.
  bool ok;

  /// Models the server offers.
  List<ModelInfo> models;

  final profiles = <ProviderProfile>[];
  final keysSeen = <String?>[];
  final probedModels = <String>[];

  LlmProvider call(ProviderProfile profile, SecretReader secrets) {
    profiles.add(profile);
    return _ServerLikeProvider(this, profile, secrets);
  }
}

final class _ServerLikeProvider implements LlmProvider {
  _ServerLikeProvider(this.f, this.profile, this.secrets);

  final RecordingFactory f;
  final ProviderProfile profile;
  final SecretReader secrets;
  final _fake = FakeLlmProvider(const []);

  @override
  ProviderType get type => profile.type;

  @override
  ProviderCapabilities get caps => _fake.caps;

  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) =>
      _fake.chat(req, cancel: cancel);

  Future<String?> _key() async {
    final auth = profile.authMethod;
    final key = auth is ApiKeyAuth ? await secrets(auth.secretRef) : null;
    f.keysSeen.add(key);
    return key;
  }

  @override
  Future<List<ModelInfo>> listModels() async {
    await _key();
    if (!f.ok) throw const AuthException('API-Key ungültig (401)');
    if (f.listError case final e?) throw e;
    return f.models;
  }

  @override
  Future<HealthCheck> test() async {
    await _key();
    f.probedModels.add(profile.defaultModel);
    final known =
        f.models.isEmpty || f.models.any((m) => m.id == profile.defaultModel);
    final ok = f.ok && known;
    return HealthCheck(
      ok: ok,
      latency: Duration.zero,
      message: !f.ok
          ? 'API-Key ungültig (401)'
          : known
          ? 'Verbindung ok'
          : 'model ${profile.defaultModel} unbekannt (404)',
      detected: ok
          ? const ProviderCapabilities(tools: true, streaming: true)
          : null,
    );
  }
}

void main() {
  group('ProviderSetupSession', () {
    ProviderSetupSession session(
      RecordingFactory f,
      SecretStore secrets, {
      String template = 'claude',
      ProviderProfile? existing,
    }) => ProviderSetupSession(
      template: providerTemplateById(template)!,
      profileId: existing?.id ?? 'p-1',
      secrets: secrets,
      create: f.call,
      ids: SequentialIdGenerator(prefix: 'k'),
      existing: existing,
    );

    test('Key nur im SecretStore; Modelle laden ohne Modell, Probe mit dem '
        'gewählten', () async {
      final secrets = InMemorySecretStore();
      final f = RecordingFactory(
        models: const [
          ModelInfo(id: 'a'),
          ModelInfo(id: 'b'),
        ],
      );
      final s = session(f, secrets);
      await s.storeKey('  $_key  ');
      expect(await secrets.read('provider.p-1.apiKey'), _key);
      final loaded = await s.loadModels();
      expect(loaded.ok, isTrue);
      expect(loaded.models.map((m) => m.id), ['a', 'b']);
      expect(f.probedModels, isEmpty, reason: 'noch keine Probe');
      final probe = await s.probe(model: 'b');
      expect(probe.ok, isTrue);
      expect(probe.detected!.tools, isTrue);
      expect(f.probedModels, ['b']);
      expect(f.keysSeen, everyElement(_key));
      expect(f.profiles.last.toJson().toString(), isNot(contains(_key)));
    });

    test('Regression: Vorlagen ohne Modellvorschlag (Ollama, eigener '
        'Endpunkt, OpenRouter, Tinfoil) kommen zur Modellwahl', () async {
      for (final template in ['ollama', 'custom', 'openrouter', 'tinfoil']) {
        final f = RecordingFactory(models: const [ModelInfo(id: 'qwen-7b')]);
        final s = session(f, InMemorySecretStore(), template: template);
        await s.storeKey(_key);
        final loaded = await s.loadModels(baseUrl: 'http://nas:11434/v1');
        expect(loaded.ok, isTrue, reason: template);
        expect(loaded.models.single.id, 'qwen-7b');
        // Der Server kennt keinen Platzhalter: geprüft wird erst das gewählte.
        expect(
          (await s.probe(baseUrl: 'http://nas/v1', model: 'qwen-7b')).ok,
          isTrue,
        );
        final wrong = await s.probe(
          baseUrl: 'http://nas/v1',
          model: 'gibtsnicht',
        );
        expect(wrong.ok, isFalse);
        expect(wrong.message, contains('404'));
      }
    });

    test('keine Modellliste (nicht Auth): weiter mit freier Eingabe', () async {
      for (final error in <ProviderException>[
        const ServerException('Not Found', statusCode: 404),
        const NetworkException('keine Verbindung'),
        const MalformedResponseException('kein JSON'),
      ]) {
        final f = RecordingFactory(listError: error);
        final s = session(f, InMemorySecretStore(), template: 'custom');
        final r = await s.loadModels(baseUrl: 'http://nas/v1');
        expect(r.ok, isTrue, reason: '$error');
        expect(r.models, isEmpty);
        expect(r.message, contains('Bitte die Modell-ID eingeben'));
        expect(
          (await s.probe(baseUrl: 'http://nas/v1', model: 'qwen')).ok,
          isTrue,
        );
      }
    });

    test('falscher Key: Modelle laden scheitert mit Meldung', () async {
      final s = session(RecordingFactory(ok: false), InMemorySecretStore());
      await s.storeKey(_key);
      final r = await s.loadModels();
      expect(r.ok, isFalse);
      expect(r.message, contains('401'));
    });

    test('ohne Key bzw. Base-URL: Meldung statt Ausnahme', () async {
      final r = await session(
        RecordingFactory(),
        InMemorySecretStore(),
      ).loadModels();
      expect(r.ok, isFalse);
      expect(r.message, contains('API-Key'));
      final custom = session(
        RecordingFactory(),
        InMemorySecretStore(),
        template: 'custom',
      );
      expect((await custom.loadModels()).message, contains('Base-URL'));
      expect((await custom.probe(model: 'x')).ok, isFalse);
    });

    test('Abbruch löscht den neuen Key, Speichern behält ihn', () async {
      final secrets = InMemorySecretStore();
      final a = session(RecordingFactory(), secrets);
      await a.storeKey(_key);
      await a.discard();
      expect(await secrets.listKeys(), isEmpty);

      final b = session(RecordingFactory(), secrets);
      await b.storeKey(_key);
      await b.commit();
      await b.discard();
      expect(await secrets.listKeys(), {'provider.p-1.apiKey'});
    });

    group('bestehendes Profil bearbeiten', () {
      final old = ProviderProfile(
        id: 'claude-7',
        name: 'Claude',
        type: ProviderType.anthropic,
        defaultModel: 'claude-haiku-5-5',
        privacy: PrivacyLevel.standard,
        authMethod: const ApiKeyAuth('provider.claude-7.apiKey'),
        options: const {'enableServerWebSearch': true},
      );

      test('ohne neuen Key bleibt der alte, Optionen bleiben', () async {
        final secrets = InMemorySecretStore();
        await secrets.write('provider.claude-7.apiKey', 'alt');
        final s = session(RecordingFactory(), secrets, existing: old);
        expect(s.keyStored, isTrue);
        final p = s.draft(model: 'claude-sonnet-5');
        expect(p.id, 'claude-7');
        expect(p.authMethod, const ApiKeyAuth('provider.claude-7.apiKey'));
        expect(p.options, {'enableServerWebSearch': true});
      });

      test('neuer Key: eigene Referenz; Abbruch behält den alten, Speichern '
          'löscht ihn', () async {
        final secrets = InMemorySecretStore();
        await secrets.write('provider.claude-7.apiKey', 'alt');
        final cancelled = session(RecordingFactory(), secrets, existing: old);
        await cancelled.storeKey('neu');
        await cancelled.discard();
        expect(await secrets.listKeys(), {'provider.claude-7.apiKey'});
        expect(await secrets.read('provider.claude-7.apiKey'), 'alt');

        final saved = session(RecordingFactory(), secrets, existing: old);
        await saved.storeKey('neu');
        final p = saved.draft(model: 'claude-haiku-5-5');
        final ref = (p.authMethod as ApiKeyAuth).secretRef;
        expect(ref, 'provider.claude-7.apiKey.k1');
        await saved.commit();
        expect(await secrets.listKeys(), {ref});
        expect(await secrets.read(ref), 'neu');
      });
    });

    test('Entwurf: Datenschutz, Budget, Warnschwelle, Name, Base-URL', () {
      final s = session(
        RecordingFactory(),
        InMemorySecretStore(),
        template: 'custom',
      );
      expect(s.needsBaseUrl, isTrue);
      final p = s.draft(
        name: ' Homeserver ',
        baseUrl: 'http://nas:8080/v1',
        model: 'qwen',
        privacy: PrivacyLevel.local,
        budgetMicros: 5000000,
        warnThreshold: 0.9,
      );
      expect(p.name, 'Homeserver');
      expect(p.baseUrl, 'http://nas:8080/v1');
      expect(p.defaultModel, 'qwen');
      expect(p.privacy, PrivacyLevel.local);
      expect(p.budgetMonthly, 5000000);
      expect(p.warnThreshold, 0.9);
      expect(p.authMethod, const NoAuth());
      expect(s.draft(model: 'qwen', baseUrl: 'http://a').warnThreshold, isNull);
    });

    test('Budget: Text ↔ Mikro-USD', () {
      expect(parseBudgetMicros(''), isNull);
      expect(parseBudgetMicros('5'), 5000000);
      expect(parseBudgetMicros(r'2,50 $'), 2500000);
      expect(() => parseBudgetMicros('viel'), throwsFormatException);
      expect(() => parseBudgetMicros('-1'), throwsFormatException);
      expect(budgetText(null), '');
      expect(budgetText(5000000), '5');
      expect(budgetText(2500000), '2,50');
      expect(budgetText(2050000), '2,05');
    });
  });

  test(
    'Speichern legt Profil und Key getrennt ab; Key nicht in der DB',
    () async {
      final dir = await Directory.systemTemp.createTemp('wendelin-wp09-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/wendelin.sqlite');
      final storage = WendelinStorage(NativeDatabase(file));
      final f = RecordingFactory(models: const [ModelInfo(id: 'claude-x')]);
      final env = TestEnv(
        storedProfiles: true,
        storage: storage,
        llmFactory: f.call,
      );
      final c = env.container();
      addTearDown(c.dispose);

      final s = ProviderSetupSession(
        template: providerTemplateById('claude')!,
        profileId: 'claude-1',
        secrets: env.secrets,
        create: c.read(llmProviderFactoryProvider),
        ids: c.read(idGeneratorProvider),
      );
      await s.storeKey(_key);
      expect((await s.loadModels()).ok, isTrue);
      expect((await s.probe(model: 'claude-x')).ok, isTrue);
      final profile = s.draft(model: 'claude-x', budgetMicros: 1000000);
      await c.read(profilesProvider.notifier).save(profile);
      await s.commit();

      final config = await c.read(storedProviderConfigProvider.future);
      expect(
        config!.primary.profileId,
        'claude-1',
        reason: 'erstes = Standard',
      );
      expect(await env.secrets.read('provider.claude-1.apiKey'), _key);
      await storage.settings.set(AppSettings.escalationChain, ['claude-1']);
      await storage.close();
      final text = String.fromCharCodes(await file.readAsBytes());
      expect(text.contains(_key), isFalse, reason: 'Key nicht in SQLite');
      expect(text.contains('claude-1'), isTrue);
    },
  );

  group('Wartung beim Start', () {
    test(
      'verwaiste provider.*-Keys werden gelöscht, benutzte bleiben',
      () async {
        final storage = openInMemoryStorage();
        final secrets = InMemorySecretStore();
        await storage.providerProfiles.save(
          ProviderProfile(
            id: 'a',
            name: 'A',
            type: ProviderType.anthropic,
            defaultModel: 'm',
            privacy: PrivacyLevel.standard,
            authMethod: const ApiKeyAuth('provider.a.apiKey'),
          ),
        );
        for (final k in [
          'provider.a.apiKey',
          'provider.weg.apiKey',
          'web.search.brave.apiKey',
        ]) {
          await secrets.write(k, 'x');
        }
        final removed = await removeOrphanProviderSecrets(storage, secrets);
        expect(removed, {'provider.weg.apiKey'});
        expect(await secrets.listKeys(), {
          'provider.a.apiKey',
          'web.search.brave.apiKey',
        });
      },
    );

    test(
      'startupMaintenance: alte Verläufe und Protokolle weg, neue bleiben',
      () async {
        final storage = openInMemoryStorage();
        final secrets = InMemorySecretStore();
        await secrets.write('provider.verwaist.apiKey', 'x');
        final old = await storage.conversations.startNew(DateTime(2020));
        await storage.conversations.append(
          old.id,
          Message.user('alt'),
          at: DateTime(2020),
        );
        final fresh = await storage.conversations.startNew(DateTime.now());
        await storage.conversations.append(fresh.id, Message.user('neu'));
        await storage.audit.record(
          AuditEntry(at: DateTime(2020), kind: AuditKind.error),
        );
        await storage.audit.record(
          AuditEntry(at: DateTime.now(), kind: AuditKind.error),
        );

        await startupMaintenance(
          storage: storage,
          secrets: secrets,
          retentionDays: 30,
        );

        expect((await storage.conversations.sessions()).map((s) => s.id), [
          fresh.id,
        ]);
        expect(await storage.audit.query(), hasLength(1));
        expect(await secrets.listKeys(), isEmpty);
      },
    );
  });

  group('ProfilesNotifier', () {
    late TestEnv env;
    late ProviderContainer c;

    ProviderProfile profile(String id, {String? secret}) => ProviderProfile(
      id: id,
      name: 'Profil $id',
      type: ProviderType.anthropic,
      defaultModel: 'claude-haiku-4-5',
      privacy: PrivacyLevel.standard,
      authMethod: secret == null ? const NoAuth() : ApiKeyAuth(secret),
    );

    setUp(() {
      env = TestEnv(
        storedProfiles: true,
        llmFactory: (p, s) => FakeLlmProvider(const []),
      );
      c = env.container();
    });
    tearDown(() => c.dispose());

    test('erstes Profil wird Standard, makeDefault wechselt', () async {
      final n = c.read(profilesProvider.notifier);
      await n.save(profile('a'));
      await n.save(profile('b'));
      expect((await c.read(profilesProvider.future)).defaultId, 'a');
      await n.save(profile('b'), makeDefault: true);
      expect((await c.read(profilesProvider.future)).defaultId, 'b');
      expect(
        (await c.read(storedProviderConfigProvider.future))!.primary.profileId,
        'b',
      );
    });

    test('Kette, Standard und Löschen räumen auf', () async {
      final n = c.read(profilesProvider.notifier);
      await env.secrets.write('provider.b.apiKey', _key);
      for (final id in ['a', 'b', 'c']) {
        await n.save(
          profile(id, secret: id == 'b' ? 'provider.b.apiKey' : null),
        );
      }
      await n.setChain(['b', 'c']);
      var state = await c.read(profilesProvider.future);
      expect(state.chain, ['b', 'c']);
      expect(
        (await c.read(storedProviderConfigProvider.future))!.chain
            .map((t) => t.profileId),
        ['b', 'c'],
      );
      await n.setDefault('c');
      state = await c.read(profilesProvider.future);
      expect(state.defaultId, 'c');
      expect(state.chain, ['b'], reason: 'Standard nicht in der Kette');

      await n.delete('b');
      state = await c.read(profilesProvider.future);
      expect(state.byId('b'), isNull);
      expect(state.chain, isEmpty);
      expect(await env.secrets.read('provider.b.apiKey'), isNull);

      await n.delete('c');
      expect((await c.read(profilesProvider.future)).defaultId, 'a');
      await n.delete('unbekannt');
    });
  });
}
