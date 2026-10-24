import '../wake/speech_gate.dart';
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
        'GitHub-Release des Wendelin-Repos (models-wake-v8a-clean); '
        'SHA-256 des Trainingslaufs v8a clean (WP143)',
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
        url: '$_wendelinRelease/models-wake-v8a-clean/$file',
        sizeBytes: 858044,
        sha256:
            '6b41519fa776f5d6c810d0323c64df86433e636d17ddb512d1a630acd9c2e58b',
      ),
    ],
  );

  /// File name of the classifier inside its model directory.
  static const file = 'wendelin_wp130_a.onnx';
}

/// Stage 1 limits of the wake word classifier per mode (WP129, rule of
/// WP133: score at or above `acceptFrom` is taken directly, from `verifyFrom`
/// up to it stage 2 checks, below it is discarded). The values are the
/// v8a working point of `docs/notes/wake-word-compare.md` with the final
/// values of WP133 (threshold 0.98 for phone and station, direct from 0.999).
/// Change them here only.
abstract final class WakeClassifierRules {
  /// WP141: observation time from the first window in the band
  /// (`CandidateWakeEngine.holdDuration`, inclusive: the window at +0.8 s
  /// still counts). A score at or above `acceptFrom` decides at once, falls
  /// do not end the hold, otherwise the peak decides at the end. Analysis of
  /// the s1 curves (WP137): 95 % of the calls reach their maximum 0.44-0.64 s
  /// after the first window at 0.98, all within 0.80 s.
  static const holdWindow = Duration(milliseconds: 800);

  /// Stage 2: audio before the hit that is transcribed (the listener default,
  /// `WakeWordListener.verifyWindow`). Provisional like the band; WP133
  /// sets the final value.
  static const verifyWindow = Duration(seconds: 2);

  /// Stage 2: audio recorded after the hit before stage 2 starts (the
  /// listener default, `WakeWordListener.verifyTail`). Provisional (WP133).
  static const verifyTail = Duration(milliseconds: 900);

  /// Stage 2 with Parakeet: the clip is scaled to [verifyPeak] before the
  /// transcription (WP133 measured a gain with the hotword setting `hw2`;
  /// a quiet call at distance reaches the model at a usable level). The
  /// pre-roll for the consumer stays as recorded.
  static const verifyNormalizeParakeet = true;

  /// Stage 2 with Whisper: no scaling (own measurement WP129: no benefit).
  static const verifyNormalizeWhisper = false;

  /// Stage 2 with Parakeet: the hotwords (WP133 `hw2`: one line „Wendelin“)
  /// and their boost in `modified_beam_search`. Change them here only.
  static const parakeetHotwords = ['Wendelin'];

  /// Boost of the hotwords of stage 2 (WP133 `hw2` = 2.0; the general
  /// default of the recognizer is 3.0).
  static const parakeetHotwordsScore = 2.0;

  /// Stage 2: target peak (fraction of full scale) of the normalization.
  static const verifyPeak = 0.5;

  /// Stage 2: clips with a smaller peak (16-bit sample value) are not scaled
  /// (digital silence or a closed room would be amplified to noise); 164 is
  /// 0.5 % of full scale, a tenth of the quietest call measured (WP129).
  static const verifyMinPeak = 164;

  /// Lower level limit (RMS of a 20 ms block, 16-bit samples) the audio of the
  /// last [silenceFloorMemory] must have reached for a main-word hit (WP126
  /// follow-up b). Measured on real recordings (WP129): quiet rooms have
  /// blocks of 9 to 93 RMS (median floor 9..18), calls of a speaker at normal
  /// distance reach at least 324 RMS; 50 keeps digital silence and a quiet
  /// room out and costs no call. It is **not** a speech detector.
  static const silenceFloorRms = 50.0;

  /// Look-back of the silence floor: the classifier decides after the word
  /// (window 1.3 s, hold up to 0.8 s), so the word must still be in memory.
  static const silenceFloorMemory = Duration(milliseconds: 2000);

  /// The silence floor of the engine (`CandidateWakeEngine.silenceFloor`),
  /// no ratio to the noise floor.
  static SpeechGate? silenceFloor() =>
      SpeechGate(minRms: silenceFloorRms, ratio: 0, memory: silenceFloorMemory);

  /// Phone: the lower limit 0.98 of the measured working point.
  static const phone = WakeScoreBand(verifyFrom: 0.98, acceptFrom: 0.999);

  /// Station (TV, longer listening): same limits as the phone (WP133 final
  /// value 0.98); stage 2 (Parakeet) catches false alarms in the band.
  static const station = WakeScoreBand(verifyFrom: 0.98, acceptFrom: 0.999);

  /// Stage 2 verifier B (WP143, result of WP137): the clip is cut
  /// [verifierBBefore] before and [verifierBAfter] after the end of the
  /// decision window of stage 1 (the peak window, `WakeWordHit.endSample`)
  /// and scaled to [verifierPeak]. Must equal the cut of the measurement.
  static const verifierBBefore = Duration(milliseconds: 1900);

  /// See [verifierBBefore].
  static const verifierBAfter = Duration(milliseconds: 850);

  /// Template cut of verifier B: seconds before the start of the speech
  /// (a double on purpose: the cut is `trunc((start - lead) * 16000)` in
  /// floating point like the measurement; the cut is padded only up to
  /// [verifierBMinTemplateSamples]).
  static const verifierBTemplateLeadSeconds = 0.12;

  /// Template cut of verifier B: seconds after the end of the speech.
  static const verifierBTemplateTailSeconds = 0.20;

  /// Template cut of verifier B: a shorter cut is padded with the real audio
  /// around it to this length (1.0 s, WP137 probe; no trim, never zeros).
  static const verifierBMinTemplateSamples = 16000;

  /// Template cut of verifier B: a longer cut (2.2 s) is discarded; only
  /// clips up to this length were measured (WP137).
  static const verifierBMaxTemplateSamples = 35200;

  /// A template of verifier B needs at least this many embedding frames
  /// (the measurement used 2-6); a template with fewer is not stored.
  static const verifierBMinTemplateFrames = 2;

  /// Verifier B: the score is the mean of the best [verifierBTopK]
  /// templates of a word; with fewer templates the mean of all of them.
  static const verifierBTopK = 3;

  /// Verifier B threshold (HW head, for both words; WP137 delivery for the
  /// model v8a clean). Unsure: on the training side it accepts about 4 % of the
  /// positives, on the test split about 60 %.
  static const verifierBThresholdHw = 0.6815;
}
