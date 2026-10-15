import 'dart:typed_data';

import 'package:meta/meta.dart';

/// What started a voice request (concept: Sprach-Pipeline, stage 1).
enum TriggerKind {
  /// Microphone button in the app.
  pushToTalk,

  /// System assistant (long press on the power button, assistant gesture,
  /// headset button).
  assistant,

  /// Wake word (from M4).
  wakeWord,

  /// Home screen widget or quick settings tile.
  widget,
}

/// One trigger, e.g. the user pressed the microphone button.
@immutable
final class TriggerEvent {
  /// Creates the event.
  const TriggerEvent({
    required this.source,
    required this.at,
    this.preRoll,
    this.wakeEnd,
  });

  /// What fired.
  final TriggerKind source;

  /// When it fired (from the injected `Clock`).
  final DateTime at;

  /// 16 kHz mono PCM captured before and up to the trigger (wake word:
  /// pre-roll, gap-free); `null` for the other sources. Not part of equality.
  final Int16List? preRoll;

  /// Sample position in [preRoll] where the wake word ends (WP68): what
  /// follows may already be the request and is judged by the VAD, the
  /// wake word itself is not. `null`: unknown, the whole pre-roll counts as
  /// silence.
  final int? wakeEnd;

  @override
  bool operator ==(Object other) =>
      other is TriggerEvent && other.source == source && other.at == at;

  @override
  int get hashCode => Object.hash(source, at);

  @override
  String toString() => 'TriggerEvent(${source.name}, $at)';
}

/// Source of triggers (implemented by the platform in the app: buttons,
/// `VoiceInteractionService`, widget, later the wake word engine).
abstract interface class TriggerSource {
  /// Broadcast stream of triggers.
  Stream<TriggerEvent> get triggers;
}
