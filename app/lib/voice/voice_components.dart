import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../di/providers.dart';
import '../di/voice_providers.dart';

/// The voice parts the app uses for push-to-talk and the overlay, or
/// `null` while speech is not available on the device (Whisper or Silero
/// not downloaded – the microphone then shows [voiceUnavailableHint]).
///
/// Device: [voiceComponentsProvider] of WP17 (`di/voice_providers.dart`:
/// `record`, Silero VAD, Whisper, system/sherpa TTS). Demo mode:
/// [demoVoiceComponents]. Read only when a voice request starts, so the
/// Whisper isolate is not loaded at app start; [voiceReadyProvider] tells
/// the UI beforehand whether the models are there.
final activeVoiceProvider = FutureProvider<VoiceComponents?>((ref) async {
  if (ref.watch(demoModeProvider)) return demoVoiceComponents();
  try {
    return await ref.watch(voiceComponentsProvider.future);
  } on VoiceException catch (e) {
    if (e.kind == VoiceErrorKind.modelMissing) return null;
    rethrow;
  }
});

/// Whether speech can start without loading anything first: demo mode, or
/// the chosen Whisper model and Silero VAD are installed.
final voiceReadyProvider = Provider<bool>((ref) {
  if (ref.watch(demoModeProvider)) return true;
  final states = ref.watch(modelStatesProvider);
  final stt =
      ref.watch(voiceSettingsProvider).value?.sttModel ??
      const VoiceSettings().sttModel;
  bool installed(String id) => states[id]?.phase == ModelPhase.installed;
  return installed(stt) && installed(SpeechModelCatalog.sileroVad.id);
});

/// Hint of the disabled microphone while speech recognition is missing.
const voiceUnavailableHint = 'Spracherkennung laden: Einstellungen → Sprache';

/// Voice error after the microphone permission was not given; the main
/// screen shows it as a card with „Erlauben“ above the input row.
const microphoneDeniedHint = 'Ohne Mikrofon-Zugriff geht nur Text.';

/// What the demo „hears“ (the demo provider understands these).
const demoPhrases = [
  'Trag mir morgen um 10 Tauchen ein',
  'Lösch den Termin',
  'Ja',
];

/// Demo mode: scripted microphone (a short utterance, then silence),
/// amplitude VAD, transcripts cycling through [phrases], no speech output
/// (the demo is silent).
VoiceComponents demoVoiceComponents({
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
  config: const VoicePipelineConfig(),
);

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
