import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../debug/wake_test_audio.dart';
import '../../di/voice_settings_providers.dart';
import '../../di/wake_providers.dart';
import '../../voice/voice_log.dart';
import '../recognizer/device_recognizer_engines.dart';
import '../recognizer/recognizer_host.dart';
import '../voice/nemo_sherpa.dart';
import '../voice/whisper_sherpa.dart';
import '../voice/whisper_stt.dart';
import 'service_audio_input.dart';
import 'wake_detector.dart';
import 'wake_host.dart';

/// Whisper of stage 2: loaded at the first candidate, freed [idleRelease]
/// after the last one (the smallest installed model: base, else small).
final class LazyWhisperVerifier implements WakeVerifier {
  /// Creates the verifier; [engines] opens the model access on first use.
  LazyWhisperVerifier({
    required this.engines,
    this.modelId = 'whisper-base',
    this.language = 'de',
  });

  /// Model access (`DeviceRecognizerEngines` on the device).
  final Future<RecognizerEngines> Function() engines;

  /// Wanted model; an installed bigger one replaces a missing one.
  final String modelId;

  /// Recognition language of the wake word.
  final String language;

  @override
  String get kind => 'whisper';

  @override
  Future<bool> confirm(Int16List pcm) async {
    final models = await engines();
    final id = await models.checkInstalled(modelId);
    // The request counts from the moment Whisper is asked for (it may fail
    // while loading).
    try {
      final stt = await models.speechToText(id);
      return await TranscriptWakeVerifier(
        stt,
        language: language,
        kind: kind,
        normalize: WakeClassifierRules.verifyNormalizeWhisper,
        onCategory: (category, ms) =>
            voiceLog('wake-verify-text', {'cat': category, 'ms': ms}),
      ).confirm(pcm);
    } finally {
      models.idle();
    }
  }
}

/// Stage 2 on Parakeet v3 with the hotword „Wendelin“ (WP129, WP133 `hw2`):
/// loaded in an own isolate at the first candidate and freed [idleRelease]
/// after the last one. Whisper (the recognizer engines) is not touched, so
/// „Stopp“ and the template path keep their model.
final class LazyParakeetVerifier implements WakeVerifier {
  /// Creates the verifier; [files] returns the paths of the installed model
  /// with the hotwords file, or `null` if Parakeet is not installed.
  LazyParakeetVerifier({
    required this.files,
    this.idleRelease = const Duration(seconds: 60),
    this.start = IsolateWhisperBackend.start,
    this.language = 'de',
  });

  /// Installed model files with hotwords, `null` = not installed.
  final Future<NemoFiles?> Function() files;

  /// How long the model stays loaded after the last candidate.
  final Duration idleRelease;

  /// Starts the backend (tests replace it).
  final Future<WhisperBackend> Function(SttSpec files) start;

  /// Recognition language (Parakeet detects it on its own).
  final String language;

  Future<WhisperBackend>? _backend;
  Timer? _idle;

  /// The last start failed (defective files, no memory): until the next
  /// [release] (after [idleRelease]) Parakeet counts as not available, so
  /// the stage falls back to Whisper instead of rejecting every hit.
  bool _loadFailed = false;

  @override
  String get kind => 'parakeet';

  /// Whether Parakeet is installed.
  Future<bool> isAvailable() async => !_loadFailed && await files() != null;

  @override
  Future<bool> confirm(Int16List pcm) async {
    _idle?.cancel();
    var loaded = false;
    try {
      final backend = await (_backend ??= _load());
      loaded = true;
      return await TranscriptWakeVerifier(
        WhisperSpeechToText(
          backend: backend,
          modelId: SpeechModelCatalog.parakeetV3.id,
          engineName: 'Parakeet (sherpa-onnx)',
        ),
        language: language,
        kind: kind,
        normalize: WakeClassifierRules.verifyNormalizeParakeet,
        onCategory: (category, ms) =>
            voiceLog('wake-verify-text', {'cat': category, 'ms': ms}),
      ).confirm(pcm);
    } on Object {
      // Neither a failed load nor a loaded isolate after a failed check may
      // stay: the first must not be cached, the second would leak (~1 GB).
      await release();
      _loadFailed = !loaded;
      rethrow;
    } finally {
      _arm();
    }
  }

  Future<WhisperBackend> _load() async {
    final spec = await files();
    if (spec == null) {
      throw const VoiceException(
        VoiceErrorKind.modelMissing,
        'Parakeet ist nicht geladen.',
      );
    }
    return start(spec);
  }

  void _arm() {
    _idle?.cancel();
    _idle = Timer(idleRelease, () => unawaited(release()));
  }

  /// Frees the model.
  Future<void> release() async {
    _idle?.cancel();
    _loadFailed = false;
    final backend = _backend;
    _backend = null;
    if (backend == null) return;
    try {
      await (await backend).dispose();
    } on Object catch (e) {
      debugPrint('Wake: Parakeet ließ sich nicht freigeben: $e');
    }
  }
}

/// Parakeet with the hotwords of stage 2 (catalog: `parakeetHotwords`,
/// `parakeetHotwordsScore`), or `null` if it is not installed or the name
/// cannot be spelled. The hotwords file holds only the fixed wake word, so
/// [hotwordsDirectory] may be a private directory of the app.
Future<NemoFiles?> wakeParakeetFiles({
  required SpeechModelService service,
  required Directory hotwordsDirectory,
}) async {
  const model = SpeechModelCatalog.parakeetV3;
  if (!await service.isInstalled(model)) return null;
  final dir = service.directoryOf(model).path;
  final bare = NemoFiles.find(model, dir);
  if (bare == null) return null;
  final hotwords = writeNemoHotwords(
    tokens: bare.tokens,
    terms: WakeClassifierRules.parakeetHotwords,
    directory: hotwordsDirectory,
    score: WakeClassifierRules.parakeetHotwordsScore,
  );
  // The measured rule needs the hotword: without it fall back to Whisper.
  if (hotwords == null) return null;
  return NemoFiles.find(model, dir, hotwords: hotwords);
}

/// The wake word parts on the device: the feature chain and the templates
/// of every learned speaker (`wakeStoreProvider`), Whisper through the
/// recognizer engines. Works without database, so the service needs no
/// drift isolate.
final class DeviceWakeParts implements WakeParts {
  /// Creates the parts on [container].
  DeviceWakeParts(
    this.container, {
    this.idleRelease = const Duration(seconds: 60),
    this.hotwordsDirectory,
    this.parakeetStart = IsolateWhisperBackend.start,
  });

  /// Directory of the hotwords file of stage 2 (default: `wake-hotwords` in
  /// the support directory).
  final Future<Directory> Function()? hotwordsDirectory;

  /// Starts the Parakeet backend (tests replace it).
  final Future<WhisperBackend> Function(SttSpec files) parakeetStart;

  /// Providers (secret store, model directory, feature chain).
  final ProviderContainer container;

  /// How long Whisper stays loaded after the last candidate.
  final Duration idleRelease;

  RecognizerEngines? _engines;
  LazyParakeetVerifier? _parakeet;

  Future<NemoFiles?> _parakeetFiles() async => wakeParakeetFiles(
    service: await container.read(speechModelServiceProvider.future),
    hotwordsDirectory: hotwordsDirectory != null
        ? await hotwordsDirectory!()
        : Directory(
            '${(await getApplicationSupportDirectory()).path}/wake-hotwords',
          ),
  );

  @override
  Future<WakeWordEngine?> engine({
    WakeDetector detector = WakeDetector.templates,
    bool station = false,
  }) async {
    if (detector == WakeDetector.model) {
      // WP129: stage 1 is the trained classifier (no templates needed); the
      // band comes from the catalog, one place for model and limits. The
      // silence floor keeps silence from being a hit (WP126 follow-up b).
      final band = wakeBandFor(station: station);
      return CandidateWakeEngine(
        features: container.read(wakeClassifierFeaturesFactoryProvider)(),
        modelThreshold: band.verifyFrom,
        directThreshold: band.acceptFrom,
        holdWindows: WakeClassifierRules.holdWindows,
        dropsToEnd: WakeClassifierRules.dropsToEnd,
        silenceFloor: WakeClassifierRules.silenceFloor(),
      );
    }
    final store = container.read(wakeStoreProvider);
    final sets = <WakeTemplates>[];
    for (final speaker in await store.speakers()) {
      final t = await store.load(speaker.id);
      if (t != null && t.embeddings.isNotEmpty) sets.add(t);
    }
    if (sets.isEmpty) return null;
    return CandidateWakeEngine(
      features: container.read(wakeFeaturesFactoryProvider)(),
      templates: sets.first,
      moreTemplates: sets.skip(1).toList(),
      // No classifier model yet (WP58): the personal templates decide.
      modelThreshold: null,
      silenceFloor: WakeClassifierRules.silenceFloor(),
    );
  }

  @override
  WakeVerifier verifier({WakeDetector detector = WakeDetector.templates}) {
    final whisper = LazyWhisperVerifier(
      engines: () async => _engines ??= DeviceRecognizerEngines(
        models: await container.read(speechModelServiceProvider.future),
        idleRelease: idleRelease,
      ),
    );
    // Templates path and „Stopp“ stay on Whisper; the classifier's stage 2
    // takes Parakeet when installed, else Whisper without a message.
    if (detector != WakeDetector.model) return whisper;
    final parakeet = _parakeet ??= LazyParakeetVerifier(
      files: _parakeetFiles,
      idleRelease: idleRelease,
      start: parakeetStart,
    );
    return PreferredWakeVerifier(
      preferred: parakeet,
      fallback: whisper,
      available: parakeet.isAvailable,
    );
  }

  @override
  Future<void> dispose() async {
    await _parakeet?.release();
    _parakeet = null;
    await _engines?.dispose();
    _engines = null;
    container.dispose();
  }
}

/// Entry of the wake word engine (`wakeWordMain` in `main.dart`).
Future<void> runWakeEngine() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(wakeEngineChannelName);
  // Device tests (debug builds) play a WAV instead of the microphone.
  final audio = await debugWakeAudio() ?? ServiceAudioInput(channel);
  if (kDebugMode && audio is! ServiceAudioInput) {
    debugPrint('Wake: Audio aus einer WAV-Datei (Gerätetest).');
  }
  await WakeHost(
    parts: DeviceWakeParts(ProviderContainer()),
    audio: audio,
  ).attach();
}
