import 'package:flutter/foundation.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../ui/design/mic_button.dart';

/// Number of waveform bars (as in the overlay design).
const waveBars = 6;

/// What the voice UI (microphone button, waveform, hints) shows.
@immutable
final class VoiceUiState {
  /// Creates a state.
  const VoiceUiState({
    this.phase = VoiceState.idle,
    this.levels = const [],
    this.trigger,
    this.hint,
    this.error,
    this.awaitingAnswer = false,
    this.preparing = false,
    this.tapOnly = false,
  });

  /// State of the voice pipeline.
  final VoiceState phase;

  /// Recent microphone levels (0–1), newest last, at most [waveBars].
  final List<double> levels;

  /// What started the current request.
  final TriggerKind? trigger;

  /// Neutral hint („Ich habe nichts verstanden.“).
  final String? hint;

  /// Why speech failed (microphone, recognition).
  final String? error;

  /// Listening for a spoken „ja“/„nein“ to an open confirmation.
  final bool awaitingAnswer;

  /// The microphone already records (and buffers) while the speech models
  /// still load (B11). Signal for a „Moment …“ display (WP31).
  final bool preparing;

  /// The open confirmation of a voice request can only be answered by tap
  /// (the spoken answer could not start or got no answer, B7).
  final bool tapOnly;

  /// Whether a voice request (or a spoken confirmation) is in progress.
  bool get active => phase != VoiceState.idle || awaitingAnswer || preparing;

  /// Whether the microphone is open.
  bool get listening =>
      phase == VoiceState.listening || awaitingAnswer || preparing;

  /// Whether an open confirmation may be answered by voice („Sag einfach
  /// ja oder nein“), otherwise only by tap („Antworte per Tipp“).
  bool get answersByVoice => active && !tapOnly;

  /// A copy with the given fields replaced (`clear…` resets to `null`).
  VoiceUiState copyWith({
    VoiceState? phase,
    List<double>? levels,
    TriggerKind? trigger,
    String? hint,
    bool clearHint = false,
    String? error,
    bool clearError = false,
    bool? awaitingAnswer,
    bool? preparing,
    bool? tapOnly,
  }) => VoiceUiState(
    phase: phase ?? this.phase,
    levels: levels ?? this.levels,
    trigger: trigger ?? this.trigger,
    hint: clearHint ? null : hint ?? this.hint,
    error: clearError ? null : error ?? this.error,
    awaitingAnswer: awaitingAnswer ?? this.awaitingAnswer,
    preparing: preparing ?? this.preparing,
    tapOnly: tapOnly ?? this.tapOnly,
  );
}

/// Microphone button state: listening (also for a spoken answer),
/// thinking while a voice or typed request runs, idle when speech is
/// [available], otherwise disabled.
MicState micStateFor(
  VoiceUiState voice, {
  required bool available,
  required bool running,
}) {
  if (voice.listening) return MicState.listening;
  if (voice.active || running) return MicState.thinking;
  return available ? MicState.idle : MicState.disabled;
}
