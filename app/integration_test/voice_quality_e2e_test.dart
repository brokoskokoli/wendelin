// Gerätetest WP103 (Bessere Sprache): Parakeet v3 erkennt eine Testaufnahme
// mit dem Hotword „Wendelin“, und die Offline-Stimmen wechseln zwischen Piper
// (Thorsten medium und high) und Kokoro (Heart, Emma, Siwis) ohne Fehler.
//
// Die Modelle liegen NICHT im Repo: Sie werden vorab in die App-Daten
// kopiert (siehe docs/testing/m5/wp103.md, Abschnitt „Gerätetest“), der
// Ordner kommt als Define. Ohne das Define wird der Test übersprungen.
//
//   WENDELIN_WP103_MODELS=wp103 \
//     tool/e2e_android.sh integration_test/voice_quality_e2e_test.dart
//
// Der Wert ist ein Ordner unter `files/e2e/` der App mit den entpackten
// Archivordnern (Name wie das Archiv ohne `.tar.bz2`) und `b6-01.wav`.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/sherpa_tts.dart';
import 'package:wendelin/platform/voice/stt_loader.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'support/voice_e2e.dart';

const _models = String.fromEnvironment('WENDELIN_WP103_MODELS');

String _base(SpeechModel m) =>
    m.files.first.name.replaceFirst(RegExp(r'\.tar\.bz2$'), '');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final skip = _models.isEmpty
      ? 'WENDELIN_WP103_MODELS nicht gesetzt (siehe docs/testing/m5/wp103.md)'
      : null;

  testWidgets(
    'Parakeet erkennt „Wendelin“ mit Hotword',
    (tester) async {
      final root = '${(await e2eDirectory()).path}/$_models';
      final backend = await tester.runAsync(
        () => startSttBackend(
          SpeechModelCatalog.parakeetV3,
          root,
          hintTerms: const ['Wendelin'],
        ),
      );
      addTearDown(() => backend!.dispose());
      final wav = Wav.parse(
        Uint8List.fromList(File('$root/b6-01.wav').readAsBytesSync()),
      );
      final result = await tester.runAsync(
        () => backend!.transcribe(pcmToFloat(wav.samples), language: 'de'),
      );
      expect(result!.text.toLowerCase(), contains('wendelin'));
    },
    skip: skip != null,
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'Stimmenwechsel Piper und Kokoro synthetisiert ohne Fehler',
    (tester) async {
      final root = '${(await e2eDirectory()).path}/$_models';
      final voices = <String, PiperVoiceFiles>{};
      for (final m in [
        SpeechModelCatalog.voiceDe,
        SpeechModelCatalog.voiceDeThorstenHigh,
        SpeechModelCatalog.voiceKokoro,
      ]) {
        final files = PiperVoiceFiles.find(
          Directory('$root/${_base(m)}'),
          kokoro: m.synth == TtsSynth.kokoro,
        );
        expect(files, isNotNull, reason: '${m.id} unvollständig in $root');
        voices[m.id] = files!;
      }
      final synth = IsolateSherpaSynthesizer(() async => voices);
      addTearDown(synth.dispose);
      const sequence = [
        'tts-de-thorsten',
        'tts-kokoro/af_heart',
        'tts-kokoro/bf_emma',
        'tts-kokoro/ff_siwis',
        'tts-de-thorsten-high',
        'tts-kokoro/af_heart',
        'tts-de-thorsten',
      ];
      for (final id in sequence) {
        final text = id.contains('ff_siwis')
            ? 'Bonjour, ceci est un essai.'
            : id.startsWith('tts-de')
            ? 'Hallo, das ist ein Test.'
            : 'Hello, this is a test.';
        final wav = await tester.runAsync(
          () => synth.synthesize(text, voiceId: id),
        );
        expect(
          wav!.duration,
          greaterThan(const Duration(milliseconds: 500)),
          reason: id,
        );
        expect(rmsLevel(wav.samples), greaterThan(0.001), reason: '$id stumm');
      }
    },
    skip: skip != null,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
