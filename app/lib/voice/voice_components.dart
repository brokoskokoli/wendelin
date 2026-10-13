import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../di/providers.dart';

/// The platform parts of the voice pipeline: microphone, VAD, speech
/// recognition and speech output.
///
/// **Interface to WP17.** WP18 (push-to-talk, overlay, voice
/// confirmations) only depends on this bundle and on
/// [voiceComponentsProvider]. WP17 (sherpa-onnx, `record`, `flutter_tts`)
/// builds the real bundle in `app/di/voice_providers.dart` and returns it
/// from the device branch of [voiceComponentsProvider]; nothing else in
/// WP18 changes.
final class VoiceComponents {
  /// Creates the bundle.
  const VoiceComponents({
    required this.audio,
    required this.vad,
    required this.stt,
    required this.textToSpeech,
    this.config = const VoicePipelineConfig(),
    this.prepare,
  });

  /// Demo mode: scripted microphone (a short utterance, then silence),
  /// amplitude VAD, transcripts cycling through [phrases], no speech
  /// output (the demo is silent).
  factory VoiceComponents.demo({
    List<String> phrases = demoPhrases,
    Duration frameInterval = const Duration(milliseconds: 30),
  }) => VoiceComponents(
    audio: FakeAudioInput(
      // 0,3 s „Sprache“, dann 0,9 s Stille: das Endpointing beendet nach
      // 800 ms Stille.
      frames: AudioFrames.pattern('S' * 10 + '.' * 30),
      frameInterval: frameInterval,
    ),
    vad: FakeVoiceActivityDetector(),
    stt: CyclingSpeechToText(phrases),
    textToSpeech: (_) async => null,
  );

  /// What the demo „hears“ (the demo provider understands these).
  static const demoPhrases = [
    'Trag mir morgen um 10 Tauchen ein',
    'Lösch den Termin',
    'Ja',
  ];

  /// Microphone (16 kHz mono PCM).
  final AudioInput audio;

  /// Voice activity detection.
  final VoiceActivityDetector vad;

  /// Speech recognition.
  final SpeechToText stt;

  /// Speech output for an answer language (`null` = text only).
  final Future<TextToSpeech?> Function(String? language) textToSpeech;

  /// Endpointing, language, stop words, TTS voice and rate (WP17:
  /// Einstellungen → Sprache).
  final VoicePipelineConfig config;

  /// Called before every recording, e.g. to ask for the microphone
  /// permission with an explanation (WP17). Returns whether recording may
  /// start; `null` = nothing to prepare.
  final Future<bool> Function()? prepare;
}

/// The voice parts in use; `null` = speech is not available (the
/// microphone button is then disabled with [voiceUnavailableHint]).
///
/// Demo mode: [VoiceComponents.demo]. Device: until WP17 is merged there
/// is no speech recognition on the device, so `null`.
// WP17: replace the device branch with the real components, e.g.
// `return ref.watch(platformVoiceComponentsProvider.future);`
final voiceComponentsProvider = FutureProvider<VoiceComponents?>((ref) async {
  if (ref.watch(demoModeProvider)) return VoiceComponents.demo();
  return null;
});

/// Hint of the disabled microphone while no speech recognition is set up.
const voiceUnavailableHint = 'Spracherkennung noch nicht eingerichtet';

/// [SpeechToText] that returns [phrases] in turn (demo mode). Silence gives
/// an empty transcript, like a real recognizer.
final class CyclingSpeechToText implements SpeechToText {
  /// Creates the recognizer.
  CyclingSpeechToText(this.phrases, {this.language = 'de'});

  /// What is „recognized“, in turn.
  final List<String> phrases;

  /// Reported language.
  final String language;

  var _next = 0;

  @override
  SpeechToTextEngineInfo get info =>
      const SpeechToTextEngineInfo(name: 'Demo', languages: {'de', 'fr', 'en'});

  @override
  Future<Transcript> transcribe(Int16List pcm, {String? language}) async {
    if (phrases.isEmpty || pcm.every((s) => s == 0)) {
      return Transcript(text: '', language: language ?? this.language);
    }
    final text = phrases[_next++ % phrases.length];
    return Transcript(
      text: text,
      language: language ?? this.language,
      confidence: 0.9,
    );
  }
}
