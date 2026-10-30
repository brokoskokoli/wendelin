import 'package:flutter/foundation.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../ui/design/mic_button.dart';

/// Number of waveform bars (as in the overlay design).
const waveBars = 6;

/// [waveBars] bars for the waveform: newest level right, flat bars to the
/// left while there are fewer levels.
List<double> waveBarsOf(List<double> levels) {
  final recent = levels.length > waveBars
      ? levels.sublist(levels.length - waveBars)
      : levels;
  return [for (var i = recent.length; i < waveBars; i++) 0.0, ...recent];
}

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
    this.stopCount = 0,
    this.followUpUntil,
    this.followUpWindow = Duration.zero,
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

  /// How often a spoken „Stopp“ aborted a request (WP31, B5); the overlay
  /// reacts to every change.
  final int stopCount;

  /// End of the follow-up window while the conversation mode listens for a
  /// follow-up question without a tap (K23 d); `null` otherwise.
  final DateTime? followUpUntil;

  /// Length of that window (for the remaining-time display).
  final Duration followUpWindow;

  /// Whether the follow-up window is open.
  bool get followUp => followUpUntil != null;

  /// Whether a voice request (or a spoken confirmation) is in progress.
  bool get active => phase != VoiceState.idle || awaitingAnswer || preparing;

  /// Whether speech output is active (WP182).
  bool get speaking => phase == VoiceState.speaking;

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
    int? stopCount,
    DateTime? followUpUntil,
    Duration? followUpWindow,
    bool clearFollowUp = false,
  }) => VoiceUiState(
    phase: phase ?? this.phase,
    levels: levels ?? this.levels,
    trigger: trigger ?? this.trigger,
    hint: clearHint ? null : hint ?? this.hint,
    error: clearError ? null : error ?? this.error,
    awaitingAnswer: awaitingAnswer ?? this.awaitingAnswer,
    preparing: preparing ?? this.preparing,
    tapOnly: tapOnly ?? this.tapOnly,
    stopCount: stopCount ?? this.stopCount,
    followUpUntil: clearFollowUp ? null : followUpUntil ?? this.followUpUntil,
    followUpWindow: clearFollowUp
        ? Duration.zero
        : followUpWindow ?? this.followUpWindow,
  );
}

/// Microphone button state: listening (also for a spoken answer),
/// preparing while the speech models load, speaking during speech output,
/// thinking while a voice or typed request runs, idle when speech is
/// [available], otherwise disabled.
MicState micStateFor(
  VoiceUiState voice, {
  required bool available,
  required bool running,
}) {
  if (voice.awaitingAnswer || voice.phase == VoiceState.listening) {
    return MicState.listening;
  }
  // Models still load while the microphone already buffers (B11).
  if (voice.preparing) return MicState.preparing;
  if (voice.phase == VoiceState.speaking) return MicState.speaking;
  if (voice.active || running) return MicState.thinking;
  return available ? MicState.idle : MicState.disabled;
}
