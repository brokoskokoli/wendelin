import '../wake/wake_score_band.dart';
import 'speech_model.dart';

const _oww =
    'https://github.com/dscripka/openWakeWord/releases/download/v0.5.1';
const _releaseNote =
    'Release-Assets sind nicht unveränderlich: wird die Datei ersetzt, '
    'schlägt die Prüfsumme fehl und der Katalog muss nachgezogen werden.';
const _wendelinRelease =
    'https://github.com/brokoskokoli/wendelin/releases/download';

/// The wake word models (features and trained classifier): model, file and limits in **one**
/// place (WP129; `SpeechModelCatalog.wakeClassifierWendelin` points here).
abstract final class WakeClassifierCatalog {
  /// openWakeWord feature models (mel spectrogram and speech embedding) for
  /// the wake word „Wendelin“ (WP44). The WP58 classifier is added as
  /// `wake-classifier-wendelin` once it passes its acceptance and is hosted.
  static const features = SpeechModel(
    id: 'wake-features',
    kind: SpeechModelKind.wake,
    displayName: 'Aktivierungswort – Merkmalsmodelle',
    languages: {},
    license: 'Apache-2.0 (openWakeWord, Google speech_embedding)',
    source:
        'GitHub-Release dscripka/openWakeWord v0.5.1; SHA-256 selbst '
        'gehasht (2026-10-14)',
    note: _releaseNote,
    attribution:
        'Merkmalsmodelle aus openWakeWord (David Scripka, Apache-2.0); das '
        'Embedding-Modell basiert auf Google speech_embedding (Apache-2.0).',
    files: [
      ModelFile(
        name: 'melspectrogram.onnx',
        url: '$_oww/melspectrogram.onnx',
        sizeBytes: 1087958,
        sha256:
            'ba2b0e0f8b7b875369a2c89cb13360ff53bac436f2895cced9f479fa65eb176f',
      ),
      ModelFile(
        name: 'embedding_model.onnx',
        url: '$_oww/embedding_model.onnx',
        sizeBytes: 1326578,
        sha256:
            '70d164290c1d095d1d4ee149bc5e00543250a7316b59f31d056cff7bd3075c1f',
      ),
    ],
  );

  /// Trained wake word classifier „Wendelin“ (v8a, WP129/WP130, K105):
  /// stage 1 on the openWakeWord features. **One place** for model id, file,
  /// hash, URL and the limits per mode ([WakeClassifierRules]); WP133 may
  /// still change model and rule.
  ///
  /// The URL is a placeholder until the release asset is uploaded (the
  /// orchestrator does that); the SHA-256 is the one of the published file,
  /// so a wrong or replaced file is refused.
  static const model = SpeechModel(
    id: 'wake-classifier-wendelin',
    kind: SpeechModelKind.wake,
    displayName: 'Aktivierungswort – trainiertes Modell „Wendelin“',
    languages: {},
    license: 'Gewichte: Wendelin-Projekt; Trainingsdaten siehe Lizenzseite',
    source:
        'GitHub-Release des Wendelin-Repos (models-wake-v8a); '
        'SHA-256 des Trainingslaufs v8a (WP130)',
    note:
        'Enthält nur Klassifikatorgewichte (ONNX), keine Aufnahmen. '
        'Trainiert auf synthetischen Stimmen (CC0, CC-BY, M-AILABS) und '
        'Aufnahmen des Maintainers aus dem Trainings-Split.',
    attribution:
        'Training mit synthetischen Stimmen (Piper, MIT): Thorsten-Voice '
        '(CC0), Multilingual LibriSpeech (Pratap et al., OpenSLR 94), '
        'CC-BY 4.0; M-AILABS Speech Dataset, Copyright (c) 2017-2019 '
        'M-AILABS (Weitergabe mit Urheberhinweis; die Daten werden ohne Gewähr '
        'bereitgestellt, die Urheber haften nicht für Schäden aus ihrer '
        'Nutzung; ihr Name dient nicht der Werbung). Negativdaten: Tatoeba-Mitwirkende, tatoeba.org '
        '(CC-BY 2.0 FR); FLEURS (Conneau et al.), CC-BY 4.0; Mozilla Common '
        'Voice (CC0). Merkmale: openWakeWord (Apache-2.0).',
    files: [
      ModelFile(
        name: file,
        url: '$_wendelinRelease/models-wake-v8a/$file',
        sizeBytes: 858044,
        sha256:
            'bfeb939d9e50c4913b27e4d082e5d620e3967af6c2603666e6bc40b30a06997d',
      ),
    ],
  );

  /// File name of the classifier inside its model directory.
  static const file = 'wendelin_wp130_a.onnx';
}

/// Stage 1 limits of the wake word classifier per mode (WP129, rule of
/// WP133: score at or above `acceptFrom` is taken directly, from `verifyFrom`
/// up to it stage 2 checks, below it is discarded). The values are the
/// v8a working point of `docs/notes/wake-word-compare.md` (threshold
/// 0.98..0.99) and the provisional upper limit of WP133; they are final only
/// with WP133. Change them here only.
abstract final class WakeClassifierRules {
  /// Windows (80 ms each) a score in the band is held to find the peak of the
  /// event; a score at or above `acceptFrom` decides at once, a fall below the
  /// peak ends the hold early.
  static const holdWindows = 5;

  /// The hold ends after this many consecutive windows below the peak
  /// (`CandidateWakeEngine.dropsToEnd`): one dip between two high windows
  /// (0.9917, 0.9892, 0.998) must not end it. Measured in WP129 on real
  /// recordings, see `docs/testing/m5/wp129.md`.
  static const dropsToEnd = 2;

  /// Stage 2: audio before the hit that is transcribed (the listener default,
  /// `WakeWordListener.verifyWindow`). Provisional like the band; WP133
  /// sets the final value.
  static const verifyWindow = Duration(seconds: 2);

  /// Stage 2: audio recorded after the hit before stage 2 starts (the
  /// listener default, `WakeWordListener.verifyTail`). Provisional (WP133).
  static const verifyTail = Duration(milliseconds: 900);

  /// Phone: the lower limit 0.98 of the measured working point.
  static const phone = WakeScoreBand(verifyFrom: 0.98, acceptFrom: 0.999);

  /// Station (TV, longer listening): the stricter end 0.99 of the working
  /// point, so fewer false alarms per hour.
  static const station = WakeScoreBand(verifyFrom: 0.99, acceptFrom: 0.999);
}
