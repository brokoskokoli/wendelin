import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/speaker_providers.dart';
import 'package:wendelin/voice/speaker/person_storage.dart';
import 'package:wendelin/voice/speaker/speaker_storage.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart'
    show MemoryCategory;
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';

SpeakerProfile testProfile(String id, String name) => SpeakerProfile(
  id: id,
  name: name,
  embeddings: [
    Float32List.fromList([1, 0, 0]),
  ],
  threshold: 0.5,
  createdAt: DateTime.utc(2026, 10, 19),
);

const _all = 'Was mag ich? Tee Koriander Kaffee';

/// Persons, memory namespaces and the person's agent (WP92b), through the
/// real controller, factory, tools and stores.
void main() {
  late FakeLlmProvider main_;
  late FakeLlmProvider cloud;
  late TestEnv env;
  late ProviderContainer c;

  Future<void> setUp0({
    List<ScriptedTurn> Function(Map<String, String> ids)? cloudTurns,
  }) async {
    final storage = openInMemoryStorage(clock: FixedClock(testNow));
    final ids = <String, String>{};
    for (final (owner, text) in const [
      ('', 'Standard mag Tee'),
      ('p:pa', 'Anna mag Koriander'),
      ('p:pb', 'Ben mag Kaffee'),
    ]) {
      ids[text] = (await storage.memory.save(
        text,
        category: StoredMemoryCategory.preference,
        source: 'user',
        owner: owner,
      )).id;
    }
    main_ = FakeLlmProvider([
      for (var i = 0; i < 6; i++) ScriptedTurn.text('ok'),
    ]);
    cloud = FakeLlmProvider(
      cloudTurns?.call(ids) ??
          [for (var i = 0; i < 6; i++) ScriptedTurn.text('ok')],
    );
    env = TestEnv(
      storage: storage,
      providerConfig: scripted(
        main_,
        id: 'main',
        name: 'Haupt',
        others: [
          ProviderTarget(
            profileId: 'cloud',
            modelId: 'cloud-m',
            provider: cloud,
            privacy: PrivacyLevel.standard,
            name: 'Cloud',
          ),
        ],
        names: const {'cloud': 'Cloud'},
      ),
    );
    final profiles = SecretSpeakerProfileStore(env.secrets);
    await profiles.save(testProfile('pa', 'Anna'));
    await profiles.save(testProfile('pb', 'Ben'));
    final settings = SecretPersonSettingsStore(env.secrets);
    await settings.save(
      const PersonSettings(
        personId: 'pa',
        address: 'Anni',
        agentProfileId: 'cloud',
      ),
    );
    await settings.save(const PersonSettings(personId: 'pb'));
    c = env.container();
    addTearDown(c.dispose);
    await c.read(toolRegistryProvider).refresh();
  }

  ConversationState controllerState() => c.read(agentControllerProvider);

  AgentController controller() => c.read(agentControllerProvider.notifier);

  Future<void> ask(String text, {String? speaker}) async {
    await controller()
        .submit(
          UserInput(text: text, source: InputSource.voice, speakerId: speaker),
        )
        .toList();
    await controller().idle;
  }

  String? sessionId() => c.read(sessionManagerProvider).currentId;

  test('Anna: Anrede, eigener Agent und nur ihr Gedächtnis', () async {
    await setUp0();
    await ask(_all, speaker: 'pa');
    expect(main_.requests, isEmpty);
    final prompt = cloud.requests.single.systemPrompt;
    expect(cloud.requests.single.model, 'cloud-m');
    expect(prompt, contains('Du sprichst mit Anni.'));
    expect(prompt, contains('Anna mag Koriander'));
    expect(prompt, isNot(contains('Standard mag Tee')));
    expect(prompt, isNot(contains('Ben mag Kaffee')));
  });

  test('ohne Anrede gilt der eingelernte Name, Standard-Agent', () async {
    await setUp0();
    await ask(_all, speaker: 'pb');
    final r = main_.requests.single;
    expect(r.systemPrompt, contains('Du sprichst mit Ben.'));
    expect(r.systemPrompt, contains('Ben mag Kaffee'));
    expect(r.systemPrompt, isNot(contains('Anna mag')));
    expect(r.systemPrompt, isNot(contains('Standard mag Tee')));
    expect(cloud.requests, isEmpty);
  });

  test('unbekannt und Tippen: wie heute (Standard-Gedächtnis, '
      'globaler Agent, keine Personen-Anrede)', () async {
    await setUp0();
    await ask(_all);
    final prompt = main_.requests.single.systemPrompt;
    expect(prompt, contains('Standard mag Tee'));
    expect(prompt, isNot(contains('Anna')));
    expect(prompt, isNot(contains('Ben')));
    expect(prompt, isNot(contains('Anni')));
    expect(cloud.requests, isEmpty);
  });

  test('geteiltes Gedächtnis: die Person sieht die Standard-Einträge, '
      'nicht die der anderen', () async {
    await setUp0();
    await SecretPersonSettingsStore(env.secrets)
        .save(const PersonSettings(personId: 'pb', sharedMemory: true));
    await ask(_all, speaker: 'pb');
    final prompt = main_.requests.single.systemPrompt;
    expect(prompt, contains('Standard mag Tee'));
    expect(prompt, isNot(contains('Ben mag Kaffee')));
    expect(prompt, isNot(contains('Anna mag')));
  });

  test('unbekannte oder gelöschte Person-Id: wie unbekannt', () async {
    await setUp0();
    await ask(_all, speaker: 'gibtsnicht');
    expect(main_.requests.single.systemPrompt, contains('Standard mag Tee'));
  });

  test('andere bekannte Person: neue Unterhaltung ohne Verlauf; unbekannt '
      'bleibt in der laufenden', () async {
    await setUp0();
    await ask('Hallo Anna-Geheimnis', speaker: 'pa');
    final annaSession = sessionId();
    await ask('Und jetzt ich', speaker: 'pb');
    final benSession = sessionId();
    expect(benSession, isNot(annaSession));
    final ben = main_.requests.single;
    expect(
      [for (final m in ben.messages) m.text].join(' '),
      isNot(contains('Anna-Geheimnis')),
    );
    // Unbekannt (Stimme nicht erkannt oder getippt): gleiche Unterhaltung,
    // gleicher Namespace, gleicher Agent.
    await ask(_all);
    expect(sessionId(), benSession);
    final follow = main_.requests.last;
    expect(follow.systemPrompt, contains('Du sprichst mit Ben.'));
    expect(follow.systemPrompt, contains('Ben mag Kaffee'));
    expect(follow.systemPrompt, isNot(contains('Anna mag')));
    expect(
      follow.messages.map((m) => m.text).join(' '),
      contains('Und jetzt ich'),
    );
    // Dieselbe Person bleibt, die erste wieder: neue Unterhaltung.
    await ask('Noch eins', speaker: 'pb');
    expect(sessionId(), benSession);
    await ask(_all, speaker: 'pa');
    expect(sessionId(), isNot(benSession));
    expect(
      cloud.requests.last.messages.map((m) => m.text).join(' '),
      isNot(contains('Und jetzt ich')),
    );
  });

  test('memory__save und Undo wirken nur im Namespace der Person', () async {
    await setUp0(
      cloudTurns: (_) => [
        ScriptedTurn.toolCalls([
          call(
            'c1',
            'memory__save',
            '{"text":"Anna fährt Rad","category":"fact"}',
          ),
        ]),
        ScriptedTurn.text('Gemerkt.'),
      ],
    );
    await ask('Merk dir, dass ich Rad fahre', speaker: 'pa');
    // Die Tools laufen über den MemoryStorePort (hier der Fake der Testumgebung).
    final memory = env.memory;
    expect(memory.entriesOf('p:pa').map((e) => e.text), ['Anna fährt Rad']);
    expect(memory.entriesOf(''), isEmpty);
    expect(memory.entriesOf('p:pb'), isEmpty);
    expect(await controller().undo('c1'), isTrue);
    expect(memory.entriesOf('p:pa'), isEmpty);
    expect(memory.entries, isEmpty);
  });

  test('memory__forget findet keine Id aus einem fremden Namespace', () async {
    await setUp0(
      cloudTurns: (_) => [
        ScriptedTurn.toolCalls([call('c1', 'memory__forget', '{"id":"m1"}')]),
        ScriptedTurn.text('Nichts.'),
      ],
    );
    final bens = await env.memory.save(
      'Ben mag Kaffee',
      category: MemoryCategory.preference,
      source: 'user',
      owner: 'p:pb',
    );
    expect(bens.id, 'm1');
    await ask('Vergiss den Kaffee', speaker: 'pa');
    expect(env.memory.entriesOf('p:pb').map((e) => e.text), ['Ben mag Kaffee']);
    final result = controllerState().entries.whereType<ToolEntry>().single;
    expect(result.phase, ToolPhase.failed);
  });

  test('Person löschen entfernt Embeddings, Einstellungen und ihre '
      'Namespace-Einträge, nicht das Standard-Gedächtnis', () async {
    await setUp0();
    expect(await env.storage.memory.count(owner: 'p:pa'), 1);
    await c.read(speakerProfilesProvider.future);
    await c.read(speakerProfilesProvider.notifier).remove('pa');
    expect(await env.storage.memory.count(owner: 'p:pa'), 0);
    expect(await env.storage.memory.count(), 1);
    expect(await env.storage.memory.count(owner: 'p:pb'), 1);
    expect(
      (await SecretSpeakerProfileStore(env.secrets).load()).map((p) => p.id),
      ['pb'],
    );
    expect((await SecretPersonSettingsStore(env.secrets).load()).keys, ['pb']);
    // Eine gelöschte Person ist unbekannt.
    await ask(_all, speaker: 'pa');
    expect(main_.requests.single.systemPrompt, contains('Standard mag Tee'));
  });

  test(
    '„Alles löschen“ der Personen entfernt alle Personen-Namespaces',
    () async {
      await setUp0();
      await c.read(speakerProfilesProvider.future);
      await c.read(speakerProfilesProvider.notifier).removeAll();
      expect(await env.storage.memory.count(owner: 'p:pa'), 0);
      expect(await env.storage.memory.count(owner: 'p:pb'), 0);
      expect(await env.storage.memory.count(), 1);
      expect(await env.secrets.listKeys(), isNot(contains('speaker.persons')));
    },
  );
}
