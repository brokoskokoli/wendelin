import 'speech_model.dart';

const _hfBase =
    'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/'
    'bb53ee204431c90d314c1cc08d28d23e5b7927cc';
const _hfSmall =
    'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/'
    '8f3c18b358db4d1f2fc1eae49d75cd20989e4309';
const _oww =
    'https://github.com/dscripka/openWakeWord/releases/download/v0.5.1';
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
    voiceFr,
    voiceFrGilles,
    voiceEn,
    voiceEnJoe,
    wakeFeatures,
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
    displayName: 'Parakeet v3 – groß, schnell, Eigennamen als Hinweis',
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

  /// German voice: Piper „Kerstin“ (low, int8; CC0 dataset of the Rhasspy
  /// project).
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

  /// French voice: Piper „Gilles“ (low, int8; CC0 dataset). The gender
  /// is taken from the voice's description, not checked by ear.
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
