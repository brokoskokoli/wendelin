import '../wake/wake_score_band.dart';
import 'speech_model.dart';

const _hfBase =
    'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/'
    'bb53ee204431c90d314c1cc08d28d23e5b7927cc';
const _hfSmall =
    'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/'
    '8f3c18b358db4d1f2fc1eae49d75cd20989e4309';
const _oww =
    'https://github.com/dscripka/openWakeWord/releases/download/v0.5.1';
const _wendelinRelease =
    'https://github.com/brokoskokoli/wendelin/releases/download';
const _gh = 'https://github.com/k2-fsa/sherpa-onnx/releases/download';

/// Whisper tokens (identical file for base and small).
const _whisperTokensSha =
    'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126';

const _hfSource =
    'Hugging Face csukuangfj (sherpa-onnx-Export), Commit gepinnt; '
    'SHA-256 der .onnx aus den LFS-Metadaten (x-linked-etag), tokens.txt '
    'selbst gehasht (2026-10-13)';
const _ghSource =
    'GitHub-Release k2-fsa/sherpa-onnx; SHA-256 aus dem Asset-Digest der '
    'GitHub-API (2026-10-13)';
const _ghNote =
    'Release-Assets sind nicht unveränderlich: wird die Datei ersetzt, '
    'schlägt die Prüfsumme fehl und der Katalog muss nachgezogen werden.';
const _int8Note =
    'int8-Variante (kleiner, schneller); Qualität auf dem Gerät prüfen '
    '(WP17), sonst auf die volle Variante wechseln.';

/// Downloadable speech models (concept: Whisper `base`/`small`, Silero VAD,
/// sherpa-onnx voices for de/fr/en).
///
/// Values were taken from the hosts' metadata on 2026-10-13 without
/// downloading the large files; see [SpeechModel.source] and
/// [SpeechModel.note] per entry.
final class SpeechModelCatalog {
  /// Creates a catalog of [models].
  const SpeechModelCatalog(this.models);

  /// The built-in catalog.
  static const standard = SpeechModelCatalog([
    whisperBase,
    whisperSmall,
    parakeetV3,
    canary180m,
    sileroVad,
    voiceDe,
    voiceDeKerstin,
    _voiceDeRamona,
    _voiceDeEva,
    voiceFr,
    voiceFrGilles,
    voiceEn,
    voiceEnJoe,
    voiceDeThorstenHigh,
    voiceKokoro,
    wakeFeatures,
    wakeClassifierWendelin,
    speakerCamPlus,
  ]);

  /// Whisper base, multilingual, int8 (fast; for weak devices).
  static const whisperBase = SpeechModel(
    id: 'whisper-base',
    kind: SpeechModelKind.stt,
    displayName: 'Whisper base – schnell, für schwache Geräte',
    languages: {'de', 'fr', 'en'},
    license: 'MIT (OpenAI Whisper)',
    source: _hfSource,
    note: _int8Note,
    ramBytes: 400 * 1024 * 1024,
    files: [
      ModelFile(
        name: 'base-encoder.int8.onnx',
        url: '$_hfBase/base-encoder.int8.onnx',
        sizeBytes: 29120534,
        sha256:
            '0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11',
      ),
      ModelFile(
        name: 'base-decoder.int8.onnx',
        url: '$_hfBase/base-decoder.int8.onnx',
        sizeBytes: 130672026,
        sha256:
            '9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d',
      ),
      ModelFile(
        name: 'base-tokens.txt',
        url: '$_hfBase/base-tokens.txt',
        sizeBytes: 816730,
        sha256: _whisperTokensSha,
      ),
    ],
  );

  /// Whisper small, multilingual, int8 (better for German, French and
  /// names; default since WP33).
  static const whisperSmall = SpeechModel(
    id: 'whisper-small',
    kind: SpeechModelKind.stt,
    displayName: 'Whisper small – genauer (empfohlen)',
    languages: {'de', 'fr', 'en'},
    license: 'MIT (OpenAI Whisper)',
    source: _hfSource,
    note: _int8Note,
    ramBytes: 1300 * 1024 * 1024,
    files: [
      ModelFile(
        name: 'small-encoder.int8.onnx',
        url: '$_hfSmall/small-encoder.int8.onnx',
        sizeBytes: 112442483,
        sha256:
            '4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9',
      ),
      ModelFile(
        name: 'small-decoder.int8.onnx',
        url: '$_hfSmall/small-decoder.int8.onnx',
        sizeBytes: 262226114,
        sha256:
            'acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee',
      ),
      ModelFile(
        name: 'small-tokens.txt',
        url: '$_hfSmall/small-tokens.txt',
        sizeBytes: 816730,
        sha256: _whisperTokensSha,
      ),
    ],
  );

  /// Parakeet TDT 0.6B v3, int8 (NeMo transducer; WP102/WP103): as exact as
  /// Whisper medium in German at the speed of base, takes hotwords. No
  /// language choice (it detects the language). Archive unpacks to
  /// `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/` with `encoder.int8.onnx`,
  /// `decoder.int8.onnx`, `joiner.int8.onnx` and `tokens.txt`.
  static const parakeetV3 = SpeechModel(
    id: 'parakeet-tdt-0.6b-v3',
    kind: SpeechModelKind.stt,
    displayName: 'Parakeet v3 – groß, schnell',
    hint: 'Schnell und genau; erkennt eigene Begriffe (Räume, Geräte, Namen).',
    languages: {'de', 'fr', 'en'},
    license: 'CC-BY-4.0 (NVIDIA)',
    source: _ghSource,
    note: _ghNote,
    attribution:
        'Spracherkennung „Parakeet TDT 0.6B v3“ von NVIDIA, CC BY 4.0; '
        'sherpa-onnx-Export (k2-fsa).',
    engine: SttEngine.nemoTransducer,
    ramBytes: 1396 * 1024 * 1024,
    files: [
      ModelFile(
        name: 'sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2',
        url:
            '$_gh/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2',
        sizeBytes: 487170055,
        sha256:
            '5793d0fd397c5778d2cf2126994d58e9d56b1be7c04d13c7a15bb1b4eafb16bf',
        archive: ModelArchive.tarBz2,
      ),
    ],
  );

  /// Canary 180M flash, int8 (NeMo, en/es/de/fr; optional, best French).
  /// Archive unpacks to `sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8/`
  /// with `encoder.int8.onnx`, `decoder.int8.onnx` and `tokens.txt`. No
  /// hotwords; the language is bound with `srcLang`.
  static const canary180m = SpeechModel(
    id: 'canary-180m-flash',
    kind: SpeechModelKind.stt,
    displayName: 'Canary flash – klein, gut für Französisch',
    hint: 'Klein und gut für Französisch; ohne eigene Begriffe.',
    languages: {'de', 'fr', 'en'},
    license: 'CC-BY-4.0 (NVIDIA)',
    source: _ghSource,
    note: _ghNote,
    attribution:
        'Spracherkennung „Canary 180M Flash“ von NVIDIA, CC BY 4.0; '
        'sherpa-onnx-Export (k2-fsa).',
    engine: SttEngine.canary,
    ramBytes: 734 * 1024 * 1024,
    files: [
      ModelFile(
        name: 'sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8.tar.bz2',
        url:
            '$_gh/asr-models/sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8.tar.bz2',
        sizeBytes: 153692328,
        sha256:
            '7a38ed8b13f014ad632b09ff8d22e0c6f1359dd046af9235d281dfae841b9ab9',
        archive: ModelArchive.tarBz2,
      ),
    ],
  );

  /// Silero VAD (v5 export of sherpa-onnx).
  static const sileroVad = SpeechModel(
    id: 'silero-vad',
    kind: SpeechModelKind.vad,
    displayName: 'Silero VAD',
    languages: {},
    license: 'MIT (Silero)',
    source: _ghSource,
    note: _ghNote,
    files: [
      ModelFile(
        name: 'silero_vad.onnx',
        url: '$_gh/asr-models/silero_vad.onnx',
        sizeBytes: 643854,
        sha256:
            '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
      ),
    ],
  );

  /// German voice: Piper „Thorsten“ (medium, int8).
  static const voiceDe = SpeechModel(
    id: 'tts-de-thorsten',
    kind: SpeechModelKind.tts,
    displayName: 'Deutsch – Thorsten (männlich)',
    gender: VoiceGender.male,
    languages: {'de'},
    license: 'CC0 (Thorsten-Voice), Piper MIT',
    source: _ghSource,
    note: '$_ghNote $_int8Note',
    files: [
      ModelFile(
        name: 'vits-piper-de_DE-thorsten-medium-int8.tar.bz2',
        url: '$_gh/tts-models/vits-piper-de_DE-thorsten-medium-int8.tar.bz2',
        sizeBytes: 20949833,
        sha256:
            '07e240b7b9c1fc9211d5a69512f8cbe11b3286c2ed79c15c076ac6ed427fdf13',
        archive: ModelArchive.tarBz2,
      ),
    ],
  );

  /// French voice: Piper „Siwis“ (medium, int8).
  static const voiceFr = SpeechModel(
    id: 'tts-fr-siwis',
    kind: SpeechModelKind.tts,
    displayName: 'Français – Siwis (weiblich)',
    gender: VoiceGender.female,
    languages: {'fr'},
    license: 'CC BY 4.0 (SIWIS-Datenbank), Piper MIT',
    source: _ghSource,
    note: '$_ghNote $_int8Note',
    attribution:
        'Stimme „Siwis“ trainiert auf der SIWIS French Speech Synthesis '
        'Database (J. Yamagishi et al., University of Edinburgh / Idiap), '
        'CC BY 4.0; Modell: Piper (rhasspy), sherpa-onnx-Export.',
    files: [
      ModelFile(
        name: 'vits-piper-fr_FR-siwis-medium-int8.tar.bz2',
        url: '$_gh/tts-models/vits-piper-fr_FR-siwis-medium-int8.tar.bz2',
        sizeBytes: 20914888,
        sha256:
            '3909cff9b3cfd4820c66aa13bf554315c82e34899c161f0b446ece372bc4b5ec',
        archive: ModelArchive.tarBz2,
      ),
    ],
  );

  /// English voice: Piper „LJSpeech“ (medium, int8; public-domain data).
  static const voiceEn = SpeechModel(
    id: 'tts-en-ljspeech',
    kind: SpeechModelKind.tts,
    displayName: 'English – LJSpeech (weiblich)',
    gender: VoiceGender.female,
    languages: {'en'},
    license: 'Public Domain (LJ Speech Dataset), Piper MIT',
    source: _ghSource,
    note: '$_ghNote $_int8Note',
    files: [
      ModelFile(
        name: 'vits-piper-en_US-ljspeech-medium-int8.tar.bz2',
        url: '$_gh/tts-models/vits-piper-en_US-ljspeech-medium-int8.tar.bz2',
        sizeBytes: 21090429,
        sha256:
            '24dc3bd77dd48c291e52c297878d3437c9492f245d823d7f6a06c4bbb67f4b6b',
        archive: ModelArchive.tarBz2,
      ),
    ],
  );

  /// German voice: Piper „Kerstin“ (low, int8; CC0, Rhasspy).
  static const voiceDeKerstin = SpeechModel(
    id: 'tts-de-kerstin',
    kind: SpeechModelKind.tts,
    displayName: 'Deutsch – Kerstin (weiblich)',
    gender: VoiceGender.female,
    languages: {'de'},
    license: 'CC0 (Rhasspy dataset-voice-kerstin), Piper MIT',
    source: _ghSource,
    note: '$_ghNote $_int8Note SHA-256 selbst gehasht (2026-10-15).',
    files: [
      ModelFile(
        name: 'vits-piper-de_DE-kerstin-low-int8.tar.bz2',
        url: '$_gh/tts-models/vits-piper-de_DE-kerstin-low-int8.tar.bz2',
        sizeBytes: 21174728,
        sha256:
            'bcd8039667940cf2efc939b844f4b33d0823096572fcc1a8caaa2faa77f3379c',
        archive: ModelArchive.tarBz2,
      ),
    ],
  );

  /// French voice: Piper „Gilles“ (low, int8; CC0), gender per description.
  static const voiceFrGilles = SpeechModel(
    id: 'tts-fr-gilles',
    kind: SpeechModelKind.tts,
    displayName: 'Français – Gilles (männlich)',
    gender: VoiceGender.male,
    languages: {'fr'},
    license: 'CC0 (Daten: French Single Speaker Speech Dataset), Piper MIT',
    source: _ghSource,
    note: '$_ghNote $_int8Note SHA-256 selbst gehasht (2026-10-15).',
    files: [
      ModelFile(
        name: 'vits-piper-fr_FR-gilles-low-int8.tar.bz2',
        url: '$_gh/tts-models/vits-piper-fr_FR-gilles-low-int8.tar.bz2',
        sizeBytes: 21248965,
        sha256:
            '92d2bfd9b6b32b9787557c466b15620e453aecc10ec521762660e034941b3c43',
        archive: ModelArchive.tarBz2,
      ),
    ],
  );

  /// English voice: Piper „Joe“ (medium, int8; CC0 dataset of the Open Home
  /// Foundation).
  static const voiceEnJoe = SpeechModel(
    id: 'tts-en-joe',
    kind: SpeechModelKind.tts,
    displayName: 'English – Joe (männlich)',
    gender: VoiceGender.male,
    languages: {'en'},
    license: 'CC0 (OHF-Voice voice-datasets), Piper MIT',
    source: _ghSource,
    note: '$_ghNote $_int8Note SHA-256 selbst gehasht (2026-10-15).',
    files: [
      ModelFile(
        name: 'vits-piper-en_US-joe-medium-int8.tar.bz2',
        url: '$_gh/tts-models/vits-piper-en_US-joe-medium-int8.tar.bz2',
        sizeBytes: 21230019,
        sha256:
            '644527f29eca0ada5595d7b6e4daf6388f5ac0c4870b4d42996a6687fcefeb37',
        archive: ModelArchive.tarBz2,
      ),
    ],
  );

  /// German voice: Piper „Thorsten“ (high, fp32; WP103). The int8 variant
  /// of the high model is slower on the Mac (WP102), so the full one is
  /// offered. Not the default: heavier (RAM about 373 MB on the Mac).
  static const voiceDeThorstenHigh = SpeechModel(
    id: 'tts-de-thorsten-high',
    kind: SpeechModelKind.tts,
    displayName: 'Deutsch – Thorsten hochwertig (männlich)',
    hint: 'Natürlicher, aber langsamer und mit mehr Speicherbedarf.',
    gender: VoiceGender.male,
    languages: {'de'},
    license: 'CC0 (Thorsten-Voice), Piper MIT',
    source: _ghSource,
    note: _ghNote,
    ramBytes: 373 * 1024 * 1024,
    files: [
      ModelFile(
        name: 'vits-piper-de_DE-thorsten-high.tar.bz2',
        url: '$_gh/tts-models/vits-piper-de_DE-thorsten-high.tar.bz2',
        sizeBytes: 115591546,
        sha256:
            'dd4ed1b0d42c30a1a4862fc2b243e8044d52b8889c9ff3d1e99e92028888bc4a',
        archive: ModelArchive.tarBz2,
      ),
    ],
  );

  /// Kokoro multi-lang v1.0, int8 (English and French; no German). One
  /// model with several speakers (`voices.bin`); the speaker ids are the
  /// positions in the model's voice list. Archive unpacks to
  /// `kokoro-int8-multi-lang-v1_0/`.
  static const voiceKokoro = SpeechModel(
    id: 'tts-kokoro',
    kind: SpeechModelKind.tts,
    displayName: 'Kokoro – Englisch und Französisch',
    hint: 'Sehr natürlich, aber langsamer; mehrere Sprecher.',
    languages: {'en', 'fr'},
    license: 'Apache-2.0 (Kokoro), Stimme ff_siwis: CC BY 4.0 (SIWIS)',
    source: _ghSource,
    note: _ghNote,
    attribution:
        'Kokoro-82M (hexgrad, Apache-2.0), sherpa-onnx-Export (k2-fsa); '
        'Stimme „ff_siwis“ nach der SIWIS French Speech Synthesis Database '
        '(J. Yamagishi et al., University of Edinburgh / Idiap), CC BY 4.0.',
    synth: TtsSynth.kokoro,
    ramBytes: 560 * 1024 * 1024,
    speakers: [
      TtsSpeaker(
        id: 'af_heart',
        language: 'en',
        name: 'Heart (weiblich, amerikanisch)',
        sid: 3,
        espeakLang: 'en-us',
        gender: VoiceGender.female,
      ),
      TtsSpeaker(
        id: 'bf_emma',
        language: 'en',
        name: 'Emma (weiblich, britisch)',
        sid: 21,
        espeakLang: 'en', // 'en-gb' kennt die espeak-Datei des Modells nicht
        gender: VoiceGender.female,
      ),
      TtsSpeaker(
        id: 'ff_siwis',
        language: 'fr',
        name: 'Siwis (weiblich)',
        sid: 30,
        espeakLang: 'fr',
        gender: VoiceGender.female,
      ),
    ],
    files: [
      ModelFile(
        name: 'kokoro-int8-multi-lang-v1_0.tar.bz2',
        url: '$_gh/tts-models/kokoro-int8-multi-lang-v1_0.tar.bz2',
        sizeBytes: 132303094,
        sha256:
            '4c3052abaa60943a341f193888cf6abd68787dae6ab8ae5c925a706caa247e4e',
        archive: ModelArchive.tarBz2,
      ),
    ],
  );

  /// openWakeWord feature models (mel spectrogram and speech embedding) for
  /// the wake word „Wendelin“ (WP44). The WP58 classifier is added as
  /// `wake-classifier-wendelin` once it passes its acceptance and is hosted.
  static const wakeFeatures = SpeechModel(
    id: 'wake-features',
    kind: SpeechModelKind.wake,
    displayName: 'Aktivierungswort – Merkmalsmodelle',
    languages: {},
    license: 'Apache-2.0 (openWakeWord, Google speech_embedding)',
    source:
        'GitHub-Release dscripka/openWakeWord v0.5.1; SHA-256 selbst '
        'gehasht (2026-10-14)',
    note: _ghNote,
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
  static const wakeClassifierWendelin = SpeechModel(
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
        'M-AILABS. Negativdaten: Tatoeba-Mitwirkende, tatoeba.org '
        '(CC-BY 2.0 FR); FLEURS (Conneau et al.), CC-BY 4.0; Mozilla Common '
        'Voice (CC0). Merkmale: openWakeWord (Apache-2.0).',
    files: [
      ModelFile(
        name: wakeClassifierFile,
        url: '$_wendelinRelease/models-wake-v8a/$wakeClassifierFile',
        sizeBytes: 858044,
        sha256:
            'bfeb939d9e50c4913b27e4d082e5d620e3967af6c2603666e6bc40b30a06997d',
      ),
    ],
  );

  /// File name of the classifier inside its model directory.
  static const wakeClassifierFile = 'wendelin_wp130_a.onnx';

  /// Speaker embedding for the speaker recognition (WP92a): 3D-Speaker
  /// CAM++ trained on Chinese and English speaker data, 192-dimensional
  /// embeddings, 16 kHz. Also usable for German (verified with synthetic
  /// voices only, check on the device).
  static const speakerCamPlus = SpeechModel(
    id: 'speaker-campplus',
    kind: SpeechModelKind.speaker,
    displayName: 'Sprechererkennung (CAM++)',
    languages: {},
    license: 'Apache-2.0 (3D-Speaker/ModelScope iic/speech_campplus_sv_zh_en_16k-common_advanced)',
    source:
        'GitHub-Release k2-fsa/sherpa-onnx „speaker-recongition-models“; '
        'SHA-256 selbst gehasht (2026-10-19)',
    note:
        '$_ghNote Trainingsdaten laut Model-Card: großer chinesischer und '
        'englischer Sprecherdatensatz (u. a. CN-Celeb, VoxCeleb), ohne '
        'eigene Lizenzangabe der Daten; die Modelldatei steht unter '
        'Apache-2.0. Erkennung kommt nicht von der Stimme allein: keine '
        'starke Authentifizierung.',
    attribution:
        'Sprechermodell CAM++ aus 3D-Speaker (Alibaba DAMO Academy, '
        'Apache-2.0), ONNX-Export von k2-fsa/sherpa-onnx.',
    ramBytes: 60 * 1024 * 1024,
    hint: 'erkennt, wer spricht (nur auf dem Gerät)',
    files: [
      ModelFile(
        name: '3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx',
        url:
            '$_gh/speaker-recongition-models/'
            '3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx',
        sizeBytes: 28281164,
        sha256:
            'aa3cfc16963a10586a9393f5035d6d6b57e98d358b347f80c2a30bf4f00ceba2',
      ),
    ],
  );

  /// All models.
  final List<SpeechModel> models;

  /// The model with [id], or `null`.
  SpeechModel? byId(String id) {
    for (final m in models) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Models of [kind].
  List<SpeechModel> ofKind(SpeechModelKind kind) => [
    for (final m in models)
      if (m.kind == kind) m,
  ];

  /// The voice for [language] (primary subtag), or `null`.
  SpeechModel? voiceFor(String language) {
    final lang = language.split(RegExp('[-_]')).first.toLowerCase();
    for (final m in ofKind(SpeechModelKind.tts)) {
      if (m.languages.contains(lang)) return m;
    }
    return null;
  }

  /// All voices for [language] (primary subtag), in catalog order; the
  /// first one is the default of [voiceFor].
  List<SpeechModel> voicesFor(String language) {
    final lang = language.split(RegExp('[-_]')).first.toLowerCase();
    return [
      for (final m in ofKind(SpeechModelKind.tts))
        if (m.languages.contains(lang)) m,
    ];
  }
}

/// German voice: Piper „Ramona“ (low, int8; M-AILABS speech dataset, BSD-style
/// license that requires keeping the copyright notice).
const _voiceDeRamona = SpeechModel(
  id: 'tts-de-ramona',
  kind: SpeechModelKind.tts,
  displayName: 'Deutsch – Ramona (weiblich)',
  gender: VoiceGender.female,
  languages: {'de'},
  license: 'BSD-3-Clause-artig (M-AILABS Speech Dataset), Piper MIT',
  source: _ghSource,
  note: '$_ghNote $_int8Note SHA-256 selbst gehasht (2026-10-21).',
  attribution:
      'Stimme „Ramona“ (low): Daten © 2017–2019 M-AILABS (Speech Dataset, '
      'https://www.caito.de/2019/01/03/the-m-ailabs-speech-dataset/), '
      'Weitergabe und Nutzung inkl. kommerziell erlaubt unter Beibehaltung '
      'des Copyright-Hinweises; Modell Piper (rhasspy/piper-voices, '
      'de/de_DE/ramona/low).',
  files: [
    ModelFile(
      name: 'vits-piper-de_DE-ramona-low-int8.tar.bz2',
      url: '$_gh/tts-models/vits-piper-de_DE-ramona-low-int8.tar.bz2',
      sizeBytes: 21199380,
      sha256:
          'e532ddcbb09c16a65f56441bbbbf301083d2ea5b18ce937775303942f2b7a8f4',
      archive: ModelArchive.tarBz2,
    ),
  ],
);

/// German voice: Piper „Eva“ (x_low, int8; M-AILABS speech dataset, BSD-style
/// license that requires keeping the copyright notice).
const _voiceDeEva = SpeechModel(
  id: 'tts-de-eva',
  kind: SpeechModelKind.tts,
  displayName: 'Deutsch – Eva (weiblich)',
  gender: VoiceGender.female,
  languages: {'de'},
  license: 'BSD-3-Clause-artig (M-AILABS Speech Dataset), Piper MIT',
  source: _ghSource,
  note: '$_ghNote $_int8Note SHA-256 selbst gehasht (2026-10-21).',
  attribution:
      'Stimme „Eva“ (x_low): Daten © 2017–2019 M-AILABS (Speech Dataset, '
      'https://www.caito.de/2019/01/03/the-m-ailabs-speech-dataset/), '
      'Weitergabe und Nutzung inkl. kommerziell erlaubt unter Beibehaltung '
      'des Copyright-Hinweises; Modell Piper (rhasspy/piper-voices, '
      'de/de_DE/eva_k/x_low).',
  files: [
    ModelFile(
      name: 'vits-piper-de_DE-eva_k-x_low-int8.tar.bz2',
      url: '$_gh/tts-models/vits-piper-de_DE-eva_k-x_low-int8.tar.bz2',
      sizeBytes: 13321491,
      sha256:
          '0501123c7e184571a40690e79943f4111a57b988632f7f60a9d2344fd061e2a2',
      archive: ModelArchive.tarBz2,
    ),
  ],
);

/// Stage 1 limits of the wake word classifier per mode (WP129, rule of
/// WP133: score at or above `acceptFrom` is taken directly, from `verifyFrom`
/// up to it stage 2 checks, below it is discarded). The values are the
/// v8a working point of `docs/notes/wake-word-compare.md` (threshold
/// 0.98..0.99) and the provisional upper limit of WP133; they are final only
/// with WP133. Change them here only.
abstract final class WakeClassifierRules {
  /// Phone: the lower limit 0.98 of the measured working point.
  static const phone = WakeScoreBand(verifyFrom: 0.98, acceptFrom: 0.995);

  /// Station (TV, longer listening): the stricter end 0.99 of the working
  /// point, so fewer false alarms per hour.
  static const station = WakeScoreBand(verifyFrom: 0.99, acceptFrom: 0.995);
}
