import 'package:wendelin_core/wendelin_core.dart';

import '../io/speech_to_text.dart';
import '../io/trigger.dart';
import 'endpointer.dart';

/// State of the `VoicePipeline` (concept: Sprach-Pipeline).
enum VoiceState {
  /// Waiting for a trigger.
  idle,

  /// Recording; VAD and endpointing decide when the utterance ends.
  listening,

  /// Speech recognition is running.
  transcribing,

  /// The agent is working (and nothing is being spoken right now).
  thinking,

  /// Speech output is playing.
  speaking,
}

/// Why a voice request was aborted.
enum VoiceCancelReason {
  /// The user tapped (overlay, button) – `VoicePipeline.cancel`.
  tap,

  /// The transcript was a stop word („Stopp“).
  stopWord,

  /// A new trigger replaced the running request.
  retrigger,

  /// The pipeline was disposed.
  disposed,
}

/// Events of the `VoicePipeline` for the UI and logs.
sealed class VoiceEvent {
  const VoiceEvent();
}

/// Listening started.
final class VoiceListening extends VoiceEvent {
  /// Creates the event.
  const VoiceListening({required this.trigger, required this.followUp});

  /// What started it (`null` for the follow-up of the conversation mode).
  final TriggerEvent? trigger;

  /// Whether this is the follow-up window of the conversation mode.
  final bool followUp;

  @override
  String toString() => 'VoiceListening($trigger, followUp: $followUp)';
}

/// Speech recognition finished.
final class VoiceTranscribed extends VoiceEvent {
  /// Creates the event.
  const VoiceTranscribed(this.transcript);

  /// The result.
  final Transcript transcript;

  @override
  String toString() => 'VoiceTranscribed($transcript)';
}

/// No usable speech („Ich habe nichts verstanden“).
final class VoiceNothingUnderstood extends VoiceEvent {
  /// Creates the event.
  const VoiceNothingUnderstood(this.reason);

  /// Why listening ended (`null` = the transcript was empty).
  final EndpointReason? reason;

  @override
  String toString() => 'VoiceNothingUnderstood(${reason?.name})';
}

/// An event of the agent run, forwarded unchanged (live text, tool cards,
/// confirmations – the UI answers `ConfirmationRequired` itself).
final class VoiceAgentEvent extends VoiceEvent {
  /// Creates the event.
  const VoiceAgentEvent(this.event);

  /// The agent event.
  final AgentEvent event;

  @override
  String toString() => 'VoiceAgentEvent($event)';
}

/// A sentence started playing.
final class VoiceSpeaking extends VoiceEvent {
  /// Creates the event.
  const VoiceSpeaking(this.sentence);

  /// The spoken text.
  final String sentence;

  @override
  String toString() => 'VoiceSpeaking($sentence)';
}

/// The request was aborted.
final class VoiceCancelled extends VoiceEvent {
  /// Creates the event.
  const VoiceCancelled(this.reason, {required this.during});

  /// Why.
  final VoiceCancelReason reason;

  /// State in which it was aborted.
  final VoiceState during;

  @override
  String toString() => 'VoiceCancelled(${reason.name}, ${during.name})';
}

/// A component failed (microphone, VAD, STT, TTS).
final class VoiceError extends VoiceEvent {
  /// Creates the event.
  const VoiceError(this.during, this.error);

  /// State in which the error happened.
  final VoiceState during;

  /// The error (usually a `VoiceException`).
  final Object error;

  @override
  String toString() => 'VoiceError(${during.name}, $error)';
}
