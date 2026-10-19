// Gerätetest WP92b (Personen: Anrede, Gedächtnis, Agent) mit synthetischen
// Stimmen. Echtes CAM++-Modell (wie speaker_e2e_test.dart, Voraussetzungen
// siehe dort und docs/testing/m5/wp92a.md), echter Controller, Werkzeuge und
// Speicher; LLM-Provider sind Fakes (keine Netzkosten, keine Keys).
//
//   handoff/wp92a-e2e/prepare.sh emulator-5554
//   WENDELIN_WP92A_DIR=wp92a \
//     tool/e2e_android.sh integration_test/speaker_persons_e2e_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/speaker_providers.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/sherpa_speaker.dart';
import 'package:wendelin/voice/speaker/person_storage.dart';
import 'package:wendelin/voice/speaker/speaker_storage.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../test/support/test_env.dart';
import 'support/voice_e2e.dart';

const _dir = String.fromEnvironment('WENDELIN_WP92A_DIR');
const _query = 'Was mag ich? Tee Koriander Kaffee';

Int16List _wav(String root, String name) =>
    Wav.parse(Uint8List.fromList(File('$root/$name.wav').readAsBytesSync()))
        .samples;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final skip = _dir.isEmpty;

  testWidgets(
    'Personen: Anrede, Gedächtnis, Agent, Wechsel, Fremdstimme, Löschen',
    (tester) async {
      Future<T> real<T>(Future<T> Function() f) async =>
          (await tester.runAsync(f)) as T;
      final root = '${(await e2eDirectory()).path}/$_dir';
      final embedder = SherpaSpeakerEmbedder(
        model: SpeechModelCatalog.speakerCamPlus,
        directory: root,
      );
      addTearDown(embedder.release);

      final storage = openInMemoryStorage(clock: FixedClock(testNow));
      for (final (owner, text) in const [
        ('', 'Standard mag Tee'),
        ('p:pt', 'Thorsten mag Koriander'),
        ('p:pk', 'Kerstin mag Kaffee'),
      ]) {
        await storage.memory.save(
          text,
          category: StoredMemoryCategory.preference,
          source: 'user',
          owner: owner,
        );
      }
      final main_ = FakeLlmProvider([
        for (var i = 0; i < 8; i++) ScriptedTurn.text('ok'),
      ]);
      final cloud = FakeLlmProvider([
        for (var i = 0; i < 8; i++) ScriptedTurn.text('ok'),
      ]);
      final env = TestEnv(
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
        extraOverrides: [speakerEmbedderProvider.overrideWithValue(embedder)],
      );
      final c = env.container();
      addTearDown(c.dispose);
      await c.read(toolRegistryProvider).refresh();
      final persons = c.read(speakerProfilesProvider.notifier);
      final identifier = c.read(speakerIdentifierProvider);

      // (1) Einlernen über den echten Notifier, danach Einstellungen.
      for (final (id, who) in const [('pt', 'thorsten'), ('pk', 'kerstin')]) {
        final r = await real(
          () => persons.enroll(
            id: id,
            name: who == 'thorsten' ? 'Thorsten' : 'Kerstin',
            samples: [
              for (var i = 1; i <= 5; i++) _wav(root, '$who-enroll-$i'),
            ],
          ),
        );
        // ignore: avoid_print
        print('WP92b enroll $who min=${r.minScore.toStringAsFixed(3)}');
      }
      final settings = SecretPersonSettingsStore(env.secrets);
      await settings.save(
        const PersonSettings(
          personId: 'pt',
          address: 'Herr Anrede',
          agentProfileId: 'cloud',
        ),
      );
      await settings.save(const PersonSettings(personId: 'pk'));
      c.invalidate(personSettingsProvider);

      Future<String?> who(String wav) async {
        final m = await real(() => identifier.identify(_wav(root, wav)));
        // ignore: avoid_print
        print(
          'WP92b identify $wav -> '
          '${m.isKnown ? m.personId : 'unbekannt'} '
          'score=${m.score?.toStringAsFixed(3)}',
        );
        return m.personId;
      }

      Future<void> ask(String text, String? speaker) async {
        final ctl = c.read(agentControllerProvider.notifier);
        await ctl
            .submit(
              UserInput(
                text: text,
                source: InputSource.voice,
                speakerId: speaker,
              ),
            )
            .toList();
        await ctl.idle;
      }

      String? session() => c.read(sessionManagerProvider).currentId;

      // (2) Thorsten: Anrede, Gedächtnis, Agent.
      final thorsten = await who('thorsten-test');
      expect(thorsten, 'pt');
      await ask('Thorsten-Geheimnis. $_query', thorsten);
      expect(main_.requests, isEmpty);
      final tReq = cloud.requests.single;
      expect(tReq.model, 'cloud-m');
      expect(tReq.systemPrompt, contains('Du sprichst mit Herr Anrede.'));
      expect(tReq.systemPrompt, contains('Thorsten mag Koriander'));
      expect(tReq.systemPrompt, isNot(contains('Kerstin mag')));
      expect(tReq.systemPrompt, isNot(contains('Standard mag Tee')));
      final tSession = session();

      // (3) Kerstin danach: neue Unterhaltung, eigener Scope, Standard-Agent
      // mit dem eingelernten Namen als Anrede.
      final kerstin = await who('kerstin-test');
      expect(kerstin, 'pk');
      await ask(_query, kerstin);
      expect(session(), isNot(tSession));
      final kReq = main_.requests.single;
      expect(kReq.systemPrompt, contains('Du sprichst mit Kerstin.'));
      expect(kReq.systemPrompt, contains('Kerstin mag Kaffee'));
      expect(kReq.systemPrompt, isNot(contains('Thorsten mag')));
      expect(kReq.systemPrompt, isNot(contains('Standard mag Tee')));
      expect(
        kReq.messages.map((m) => m.text).join(' '),
        isNot(contains('Thorsten-Geheimnis')),
      );
      expect(cloud.requests, hasLength(1));
      final kSession = session();

      // (4) Fremdstimme: unbekannt, bleibt in Kerstins Unterhaltung. Nach
      // neuem Thema: Standard (Anrede aus Einstellungen, Standard-Gedächtnis,
      // globaler Agent).
      expect(await who('miro-test'), isNull);
      await ask(_query, null);
      expect(session(), kSession);
      await c.read(agentControllerProvider.notifier).newTopic();
      await ask(_query, null);
      final uReq = main_.requests.last;
      expect(uReq.systemPrompt, contains('Standard mag Tee'));
      expect(uReq.systemPrompt, isNot(contains('Kerstin')));
      expect(uReq.systemPrompt, isNot(contains('Thorsten')));
      expect(uReq.systemPrompt, isNot(contains('Herr Anrede')));
      expect(cloud.requests, hasLength(1));

      // (5) Person löschen: Embeddings, Einstellungen, Namespace weg.
      expect(await storage.memory.count(owner: 'p:pt'), 1);
      await real(() => persons.remove('pt'));
      expect(await storage.memory.count(owner: 'p:pt'), 0);
      expect(await storage.memory.count(owner: 'p:pk'), 1);
      expect(await storage.memory.count(), greaterThan(0));
      expect(await who('thorsten-test'), isNull);
      expect(await who('kerstin-test'), 'pk');
      expect((await settings.load()).keys, ['pk']);
      final raw = jsonEncode(
        (await SecretSpeakerProfileStore(
          env.secrets,
        ).load()).map((p) => p.id).toList(),
      );
      expect(raw, isNot(contains('pt')));
      await real(persons.removeAll);
      expect(await storage.memory.count(owner: 'p:pk'), 0);
      expect(await settings.load(), isEmpty);
      expect(await who('kerstin-test'), isNull);
      expect(await env.secrets.listKeys(), isEmpty);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
