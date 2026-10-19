// Gerätetest M2 (WP19): Push-to-talk im Hauptbildschirm mit einer WAV statt
// des Mikrofons → Whisper lokal (base und small) → Agent mit Skript-Provider
// → `obsidian__append_daily_note` ergänzt die Tagesnotiz im SAF-Test-Vault
// byte-genau; danach Rückgängig. Dazu die Laufzeitmessung Whisper base/small
// auf den STT-Fixtures.
//
// Nur mit `WENDELIN_MODELS=<dir> tool/e2e_android.sh
// integration_test/voice_note_e2e_test.dart`: das Skript kopiert Whisper
// base/small, Silero und die WAVs in die App-Daten, erteilt die
// Mikrofon-Berechtigung und bedient die Ordnerauswahl.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/debug/device_test_overrides.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/platform/saf_vault_port.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/wav_audio_input.dart';
import 'package:wendelin/platform/voice/whisper_stt.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'support/e2e.dart';
import 'support/voice_e2e.dart';

/// Was der Skript-Provider einträgt (unabhängig von der Erkennung).
const _line = '- Zahnarzt angerufen';

/// Fixtures der Messung (je Sprache die Befehle 01–10, Manifest in
/// `app/test/fixtures/stt/manifest.tsv`).
final _measured = [
  for (final lang in ['de', 'fr', 'en'])
    for (var i = 1; i <= 10; i++) '$lang-${i.toString().padLeft(2, '0')}',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late PickedVault vault;
  late SafVaultPort port;

  setUpAll(() async {
    if (!voiceE2e) return;
    await waitForDeviceFiles();
    vault = await pickTestVault();
    port = vaultPort(vault);
  });
  tearDownAll(() async {
    if (!voiceE2e) return;
    if (await port.exists(testDailyNote)) await port.delete(testDailyNote);
    await const VaultAccess().release(vault.uri);
  });

  for (final model in ['whisper-base', 'whisper-small']) {
    testWidgets(
      '$model: gesprochene Bitte (WAV) ergänzt die Tagesnotiz byte-genau',
      (tester) async {
        await resetTestNote(port);
        final audio = WavAudioInput.file(await fixtureWav('de-05'));
        final provider = FakeLlmProvider([
          ScriptedTurn.toolCalls([
            ToolCallBlock(
              id: 'n1',
              name: 'obsidian__append_daily_note',
              argumentsJson: jsonEncode(appendArgs(_line)),
            ),
          ]),
          ScriptedTurn.text('Steht in deiner Tagesnotiz.'),
        ]);
        final app = E2eApp(
          startup: StartupSettings(
            enabledIntegrations: const {'obsidian'},
            obsidian: testObsidian(vault),
          ),
          config: (_) => deviceTestProviderConfig(provider),
          extraOverrides: [audioInputProvider.overrideWithValue(audio)],
        );
        await app.storage.settings.set(
          voiceSettingsKey,
          VoiceSettings(sttModel: model),
        );
        final c = await app.pump(tester);
        // Modelle werden erkannt (Mikrofon aktiv statt „Spracherkennung laden“).
        await pumpUntil(
          tester,
          find.byWidgetPredicate(
            (w) => w is MicButton && w.state == MicState.idle,
          ),
        );

        await tester.tap(find.byType(MicButton));
        // Das Transkript erscheint als Nutzernachricht.
        await pumpUntil(
          tester,
          find.textContaining(RegExp('[Zz]ahnarzt')),
          timeout: const Duration(seconds: 90),
        );
        final heard = DateTime.now();
        await pumpUntil(tester, find.text('Steht in deiner Tagesnotiz.'));
        expect(
          await port.read(testDailyNote),
          testNoteAfter([_line]),
          reason: 'BOM, CRLF und fehlender Schlussumbruch bleiben',
        );

        final stt = await c.read(speechToTextProvider.future);
        final timing = (stt as WhisperSpeechToText).lastTiming!;
        expect(timing.modelId, model);
        expect(timing.language, 'de', reason: 'feste Sprache „Wie die App“');
        final audit = await auditText(app);
        expect(audit, contains('obsidian__append_daily_note'));
        expect(audit, contains('pushToTalk'));
        expect(audio.starts, 1);
        // ignore: avoid_print
        print(
          'M2-Messung push-to-talk $model: $timing; Ende der Aufnahme bis '
          'Transkript sichtbar ${heard.difference(audio.endOfRecording!).inMilliseconds} ms',
        );

        // Rückgängig stellt den alten Stand byte-genau wieder her.
        await tester.tap(undoButton(tester));
        await pumpUntil(tester, find.text(l10n(tester).toolResultUndone));
        expect(await port.read(testDailyNote), testNoteBefore);
        await waitIdle(tester);
      },
      skip: !voiceE2e,
    );
  }

  // WP33/B6: D2 mit whisper-base. Der Skript-Provider übernimmt den
  // Notiznamen aus dem Transkript (wie ein Modell); gefunden wird die Notiz
  // über die Vokabular-Korrektur bzw. die phonetische Titelsuche. Nur
  // b6-01 (Anna): Bei Reed/Flo erkennt base schon „Notiz“ nicht mehr
  // („Was steht in meiner Gute? Es ist mit der Intest.“).
  for (final fixture in ['b6-01']) {
    testWidgets('whisper-base: D2 ($fixture) findet die Notiz Wendelin-Test', (
      tester,
    ) async {
      const note = 'Wendelin-Test.md';
      if (await port.exists(note)) {
        await port.write(note, _b6Note);
      } else {
        await port.create(note, _b6Note);
      }
      final audio = WavAudioInput.file(await fixtureWav(fixture));
      final provider = _NoteNameProvider();
      final app = E2eApp(
        startup: StartupSettings(
          enabledIntegrations: const {'obsidian'},
          obsidian: testObsidian(vault),
        ),
        config: (_) => deviceTestProviderConfig(provider),
        extraOverrides: [audioInputProvider.overrideWithValue(audio)],
      );
      await app.storage.settings.set(
        voiceSettingsKey,
        const VoiceSettings(sttModel: 'whisper-base'),
      );
      // Der Index kennt die Notiz (sonst baut ihn die erste Suche auf).
      await app.storage.notes.upsert(
        note,
        title: 'Wendelin-Test',
        body: _b6Note,
        modifiedAt: DateTime.utc(2030, 3, 12),
      );
      await app.pump(tester);
      await pumpUntil(
        tester,
        find.byWidgetPredicate(
          (w) => w is MicButton && w.state == MicState.idle,
        ),
      );
      await tester.tap(find.byType(MicButton));
      await pumpUntil(
        tester,
        find.text('Gefunden.'),
        timeout: const Duration(seconds: 90),
      );
      // ignore: avoid_print
      print(
        'WP33 D2 $fixture base: Transkript „${provider.heard}“, '
        'Notizname „${provider.asked}“',
      );
      final result = provider.toolResult!;
      expect(result, contains('<note_content path="$note"'));
      expect(result, contains('offen'));
      expect(await auditText(app), contains('obsidian__read_note'));
      await waitIdle(tester);
      await port.delete(note);
    }, skip: !voiceE2e);
  }

  testWidgets(
    'Laufzeit Whisper base/small (feste Sprache) auf den STT-Fixtures',
    (tester) async {
      final lines = <String>[];
      for (final model in ['whisper-base', 'whisper-small']) {
        final app = E2eApp(startup: const StartupSettings());
        await app.storage.settings.set(
          voiceSettingsKey,
          VoiceSettings(sttModel: model),
        );
        final c = await app.pump(tester);
        final load = Stopwatch()..start();
        final stt = await c.read(speechToTextProvider.future);
        // Erster Lauf lädt die Gewichte in den Speicher (zählt zum Kaltstart).
        await stt.transcribe(
          Wav.read(await fixtureWav('de-11')).samples,
          language: 'de',
        );
        load.stop();
        var audioMs = 0;
        var computeMs = 0;
        final perLang = <String, List<int>>{};
        for (final id in _measured) {
          final wav = Wav.read(await fixtureWav(id));
          // Wie in der App: 300 ms Vorlauf und 800 ms Endstille.
          final samples = Int16List(4800 + wav.samples.length + 12800)
            ..setRange(4800, 4800 + wav.samples.length, wav.samples);
          await stt.transcribe(samples, language: id.substring(0, 2));
          final t = (stt as WhisperSpeechToText).lastTiming!;
          audioMs += t.audio.inMilliseconds;
          computeMs += t.compute.inMilliseconds;
          (perLang[id.substring(0, 2)] ??= []).add(t.compute.inMilliseconds);
        }
        final n = _measured.length;
        lines.add(
          'M2-Messung $model: Kaltstart (Laden + erster Satz) '
          '${load.elapsedMilliseconds} ms; $n Sätze, Ø Audio '
          '${audioMs ~/ n} ms, Ø Rechenzeit ${computeMs ~/ n} ms, '
          'RTF ${(computeMs / audioMs).toStringAsFixed(2)}; '
          '${[for (final e in perLang.entries) '${e.key} Ø ${e.value.reduce((a, b) => a + b) ~/ e.value.length} ms / max ${e.value.reduce((a, b) => a > b ? a : b)} ms'].join(', ')}',
        );
        // Whisper-Isolat freigeben, bevor das nächste Modell lädt.
        await tester.pumpWidget(const SizedBox());
      }
      // ignore: avoid_print
      lines.forEach(print);
      // ignore: avoid_print
      print(
        'M2-Messung Gerät: ${Platform.operatingSystemVersion}, '
        '${Platform.numberOfProcessors} Kerne',
      );
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

const _b6Note = '# Wendelin-Test\n\n## Status\n\noffen\n';

/// Plays a model that reads the note named in the spoken request: the
/// first turn calls `obsidian__read_note` with the words after „Notiz“
/// from the transcript, the second answers „Gefunden.“.
final class _NoteNameProvider implements LlmProvider {
  final _inner = FakeLlmProvider(const []);

  /// What Whisper heard (after the correction).
  String? heard;

  /// The note name passed to the tool.
  String? asked;

  /// The tool result of `obsidian__read_note`.
  String? toolResult;

  @override
  ProviderType get type => _inner.type;

  @override
  ProviderCapabilities get caps => _inner.caps;

  @override
  Future<List<ModelInfo>> listModels() => _inner.listModels();

  @override
  Future<HealthCheck> test() => _inner.test();

  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) {
    final last = req.messages.last.content;
    final results = last.whereType<ToolResultBlock>();
    if (results.isNotEmpty) {
      toolResult = results.first.content
          .whereType<TextBlock>()
          .map((b) => b.text)
          .join();
      _inner.enqueue(ScriptedTurn.text('Gefunden.'));
    } else {
      heard = last.whereType<TextBlock>().map((b) => b.text).join();
      asked = RegExp(r'Notiz\s*(.+?)[\s?.!]*$').firstMatch(heard!)?[1] ?? heard;
      _inner.enqueue(
        ScriptedTurn.toolCalls([
          ToolCallBlock(
            id: 'r1',
            name: 'obsidian__read_note',
            argumentsJson: jsonEncode({'path': asked}),
          ),
        ]),
      );
    }
    return _inner.chat(req, cancel: cancel);
  }
}
