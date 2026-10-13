// Misst die Wortfehlerrate (WER) von Whisper base/small auf den
// STT-Fixtures (app/test/fixtures/stt) über die sherpa-onnx-Desktop-Bindings.
//
//   cd app
//   dart run tool/stt_wer.dart --models <dir> [--model whisper-base]
//       [--fixtures test/fixtures/stt] [--threads 4]
//
// <dir> enthält je Modell einen Ordner mit den Dateien aus dem Katalog
// (z. B. <dir>/whisper-base/base-encoder.int8.onnx). Die Modelle werden
// nicht eingecheckt. Ausgabe: Markdown-Tabellen auf stdout (für
// docs/notes/stt-wer-<datum>.md), je Satz die Erkennung auf stderr.
//
// Jede Aufnahme bekommt die Stille, die der Endpointer mitliefert (300 ms
// Pre-Roll, 800 ms Endstille). Gemessen wird über `WhisperSpeechToText` (dieselbe Bereinigung wie in der
// App), einmal mit automatischer Spracherkennung und einmal mit fester
// Sprache. Auf dem Emulator/Gerät läuft dieselbe Messung mit
// `integration_test` nicht; dort genügt ein Stichprobentest.
import 'dart:io';
import 'dart:typed_data';

import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/wer.dart';
import 'package:wendelin/platform/voice/whisper_sherpa.dart';
import 'package:wendelin/platform/voice/whisper_stt.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

Future<void> main(List<String> args) async {
  String? opt(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final modelsDir = opt('models') ?? Platform.environment['WENDELIN_MODELS'];
  if (modelsDir == null) {
    stderr.writeln('--models <dir> fehlt');
    exitCode = 64;
    return;
  }
  final fixtures = opt('fixtures') ?? 'test/fixtures/stt';
  final threads = int.tryParse(opt('threads') ?? '') ?? 4;
  final only = opt('model');
  final samples = loadFixtures(fixtures);
  stderr.writeln('${samples.length} Fixtures aus $fixtures');

  final models = [
    SpeechModelCatalog.whisperBase,
    SpeechModelCatalog.whisperSmall,
  ].where((m) => only == null || m.id == only);

  final rows = <String>[];
  final langs = ['de', 'fr', 'en'];
  for (final model in models) {
    final dir = '$modelsDir/${model.id}';
    if (!Directory(dir).existsSync()) {
      stderr.writeln('$dir fehlt, übersprungen');
      continue;
    }
    final engine = SherpaWhisperEngine(
      WhisperFiles.of(model, dir),
      threads: threads,
    );
    final stt = WhisperSpeechToText(
      backend: _Direct(engine),
      modelId: model.id,
    );
    for (final fixed in [false, true]) {
      final perLang = {for (final l in langs) l: WerCounter()};
      var audioMs = 0;
      var cpuMs = 0;
      for (final s in samples) {
        final watch = Stopwatch()..start();
        final t = await stt.transcribe(
          s.pcm,
          language: fixed ? s.language : null,
        );
        cpuMs += watch.elapsedMilliseconds;
        audioMs += samplesToDuration(s.pcm.length).inMilliseconds;
        final errors = wordErrors(s.text, t.text, s.language);
        perLang[s.language]!.add(errors, sentence: s.id);
        stderr.writeln(
          '${model.id} ${fixed ? 'fest' : 'auto'} ${s.id} '
          '[${t.language} ${t.confidence?.toStringAsFixed(2)}] '
          '${errors.errors}/${errors.words}: ${t.text}',
        );
      }
      final all = WerCounter();
      for (final c in perLang.values) {
        all.merge(c);
      }
      rows.add(
        '| ${model.id} | ${fixed ? 'fest' : 'automatisch'} | '
        '${[for (final l in langs) perLang[l]!.percent].join(' | ')} | '
        '${all.percent} | ${all.exact}/${all.sentences} | '
        '${(cpuMs / samples.length).round()} ms | '
        '${(cpuMs / audioMs).toStringAsFixed(2)} |',
      );
    }
    engine.dispose();
  }

  stdout
    ..writeln(
      '| Modell | Sprache | WER de | WER fr | WER en | WER gesamt | '
      'Sätze fehlerfrei | Ø Zeit/Satz | RTF |',
    )
    ..writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|');
  rows.forEach(stdout.writeln);
}

/// A fixture: id, language, reference text and audio.
typedef Fixture = ({String id, String language, String text, Int16List pcm});

/// Reads `manifest.tsv` and the WAV files next to it.
List<Fixture> loadFixtures(String dir) => [
  for (final line in File('$dir/manifest.tsv').readAsLinesSync())
    if (line.trim().isNotEmpty && !line.startsWith('#'))
      _fixture(dir, line.split('\t')),
];

Fixture _fixture(String dir, List<String> cols) => (
  id: cols[0],
  language: cols[1],
  text: cols[3],
  pcm: padLikeEndpointer(Wav.read('$dir/${cols[0]}.wav').samples),
);

/// [speech] with the silence the `Endpointer` keeps around an utterance:
/// 300 ms pre-roll before and 800 ms end silence after it (the `say`
/// recordings start and end without a pause; Whisper then drops the first
/// or last syllable).
Int16List padLikeEndpointer(Int16List speech) {
  const before = 4800, after = 12800;
  return Int16List(before + speech.length + after)
    ..setRange(before, before + speech.length, speech);
}

final class _Direct implements WhisperBackend {
  _Direct(this.engine);

  final SherpaWhisperEngine engine;

  @override
  Future<WhisperResult> transcribe(
    Float32List samples, {
    String? language,
  }) async => engine.transcribe(samples, language: language);

  @override
  Future<void> dispose() async {}
}
