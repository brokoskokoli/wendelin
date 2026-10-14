import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../debug/wake_test_audio.dart';
import '../../di/voice_settings_providers.dart';
import '../../di/wake_providers.dart';
import '../recognizer/device_recognizer_engines.dart';
import '../recognizer/recognizer_host.dart';
import 'service_audio_input.dart';
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
  Future<bool> confirm(Int16List pcm) async {
    final models = await engines();
    final id = await models.checkInstalled(modelId);
    // The request counts from the moment Whisper is asked for (it may fail
    // while loading).
    try {
      final stt = await models.speechToText(id);
      return await TranscriptWakeVerifier(stt, language: language).confirm(pcm);
    } finally {
      models.idle();
    }
  }
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
  });

  /// Providers (secret store, model directory, feature chain).
  final ProviderContainer container;

  /// How long Whisper stays loaded after the last candidate.
  final Duration idleRelease;

  RecognizerEngines? _engines;

  @override
  Future<WakeWordEngine?> engine() async {
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
    );
  }

  @override
  WakeVerifier verifier() => LazyWhisperVerifier(
    engines: () async => _engines ??= DeviceRecognizerEngines(
      models: await container.read(speechModelServiceProvider.future),
      idleRelease: idleRelease,
    ),
  );

  @override
  Future<void> dispose() async {
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
