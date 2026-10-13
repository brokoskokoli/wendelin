import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/vocabulary_provider.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'voice_controller_test.dart' show fakeVoice, utterance;

/// Collects `debugPrint` output while [body] runs.
Future<List<String>> capturePrints(Future<void> Function() body) async {
  final lines = <String>[];
  final original = debugPrint;
  debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
  try {
    await body();
  } finally {
    debugPrint = original;
  }
  return lines;
}

Future<void> _index(TestEnv env, List<String> paths) async {
  for (final p in paths) {
    await env.storage.notes.upsert(
      p,
      title: VaultPath.title(p),
      body: 'geheimer Inhalt',
      modifiedAt: DateTime.utc(2026, 10, 13),
    );
  }
}

void main() {
  group('VocabularySource', () {
    test('Assistentenname, Notiztitel, Listen; neu nur bei Änderung', () async {
      var paths = ['Projekte/Wendelin-Test.md', 'Reisen/Malta 2026.md'];
      var lists = ['Einkaufen', 'Wocheneinkauf Markt'];
      final source = VocabularySource(
        notePaths: () async => paths,
        listNames: () => lists,
      );
      final v1 = await source.current();
      expect(v1.terms.map((t) => t.text), [
        'Wendelin',
        'Wendelin-Test',
        'Malta 2026',
        'Wocheneinkauf Markt',
      ]);
      // Einwortige Titel und Listen werden nicht korrigiert.
      expect(v1.terms.map((t) => t.text), isNot(contains('Einkaufen')));
      expect(identical(await source.current(), v1), isTrue);

      paths = [...paths.reversed];
      expect(
        identical(await source.current(), v1),
        isTrue,
        reason: 'Reihenfolge des Index egal',
      );

      lists = ['Baumarkt Liste'];
      final v2 = await source.current();
      expect(identical(v2, v1), isFalse);
      expect(v2.terms.map((t) => t.text), contains('Baumarkt Liste'));
    });

    test('Index nicht lesbar: letztes Vokabular, Log ohne Namen', () async {
      var fail = false;
      final source = VocabularySource(
        notePaths: () async => fail
            ? throw StateError('Wendelin-Test kaputt')
            : ['Geheim-Projekt.md'],
        listNames: () => const [],
      );
      final v1 = await source.current();
      fail = true;
      late Vocabulary v2;
      final log = await capturePrints(() async => v2 = await source.current());
      expect(identical(v2, v1), isTrue);
      expect(log.single, contains('Notizindex nicht lesbar'));
      expect(log.single, isNot(contains('Geheim')));
      expect(log.single, isNot(contains('Wendelin-Test')));
    });
  });

  test('voiceComponentsProvider korrigiert mit dem Notizindex', () async {
    final env = TestEnv(
      extraOverrides: [
        speechToTextProvider.overrideWith(
          (ref) async => FakeSpeechToText([
            const Transcript(text: 'Lies Wandel Intest vor', language: 'de'),
          ]),
        ),
        voiceActivityDetectorProvider.overrideWith(
          (ref) async => FakeVoiceActivityDetector(),
        ),
      ],
    );
    await _index(env, ['Projekte/Wendelin-Test.md']);
    final c = env.container();
    addTearDown(c.dispose);
    final components = await c.read(voiceComponentsProvider.future);
    expect(components.stt, isA<CorrectingSpeechToText>());
    final t = await components.stt.transcribe(utterance().first);
    expect(t.text, 'Lies Wendelin-Test vor');
    // Der eingesetzte Titel ist für die Obsidian-Tools markiert (B8).
    final corrected = c.read(correctedTitlesProvider);
    expect(corrected.take('Projekte/Wendelin-Test.md'), isTrue);
    expect(corrected.take('Projekte/Wendelin-Test.md'), isFalse);
  });

  test('CorrectedTitles: nur Titel, je Erkennung ersetzt', () {
    final v = Vocabulary(
      ['Wendelin-Test', 'Urlaub Ideen'],
      names: ['Wendelin'],
    );
    final c = CorrectedTitles()..record(v.terms);
    expect(c.take('Wendelin.md'), isFalse, reason: 'Assistentenname');
    expect(c.take('A/Wendelin Test.md'), isTrue);
    c.record(const []);
    expect(c.take('Urlaub Ideen.md'), isFalse);
  });

  test('Obsidian-Integration fragt beim Schreiben nach (Verdrahtung)', () {
    final env = TestEnv();
    final c = env.container();
    addTearDown(c.dispose);
    final deps = c.read(integrationDepsProvider);
    final integration =
        builtInIntegrationSpecs
                .singleWhere((s) => s.id == 'obsidian')
                .create(deps)
            as ObsidianIntegration;
    c.read(correctedTitlesProvider).record(Vocabulary(['Wendelin-Test']).terms);
    expect(integration.env.spokenCorrection!('Wendelin-Test.md'), isTrue);
    expect(integration.env.spokenCorrection!('Wendelin-Test.md'), isFalse);
  });

  test(
    'Datenschutz: Vokabular und Korrektur weder im Log noch im Audit',
    () async {
      final provider = FakeLlmProvider([ScriptedTurn.text('Status: offen.')]);
      late final TestEnv env;
      env = TestEnv(
        providerConfig: scripted(provider),
        extraOverrides: [
          activeVoiceProvider.overrideWith((ref) async {
            final v = fakeVoice(
              script: const [
                Transcript(
                  text: 'Was steht in meiner Notiz Wandel Intest?',
                  language: 'de',
                  confidence: 0.7,
                ),
              ],
            );
            return VoiceComponents(
              audio: v.audio,
              vad: v.vad,
              stt: CorrectingSpeechToText(
                v.stt,
                vocabulary: ref.read(vocabularySourceProvider).current,
              ),
              textToSpeech: v.textToSpeech,
              config: v.config,
            );
          }),
        ],
      );
      await _index(env, [
        'Projekte/Wendelin-Test.md',
        'Privat/Geheimprojekt Phoenix.md',
      ]);
      final c = env.container();
      addTearDown(c.dispose);
      final log = await capturePrints(() async {
        final voice = c.read(voiceControllerProvider.notifier);
        expect(await voice.start(TriggerKind.pushToTalk), isTrue);
        await voice.whenIdle;
        await c.read(auditRecorderProvider).flush();
      });

      const corrected = 'Was steht in meiner Notiz Wendelin-Test?';
      expect(
        c
            .read(agentControllerProvider)
            .entries
            .whereType<UserEntry>()
            .single
            .text,
        corrected,
      );
      expect(
        provider.requests.single.messages.last.content
            .whereType<TextBlock>()
            .single
            .text,
        corrected,
      );

      // Nichts aus dem Vokabular und nichts von der Korrektur im Log.
      for (final secret in ['Wandel', 'Wendelin-Test', 'Geheimprojekt']) {
        expect(log.where((l) => l.contains(secret)), isEmpty, reason: secret);
      }

      // Audit: nur die Anfrage mit dem Text, der an das Modell ging.
      final audit = await env.storage.audit.query();
      final request = audit.singleWhere((e) => e.kind == AuditKind.request);
      expect(request.payload['text'], corrected);
      final all = jsonEncode([for (final e in audit) e.payload]);
      expect(all, isNot(contains('Wandel Intest')));
      expect(all, isNot(contains('Geheimprojekt')));
      expect('Wendelin-Test'.allMatches(all).length, 1);
    },
  );
}
