import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import '../io/trigger.dart';
import 'wake_word_listener.dart';

/// [TriggerSource] of the wake word: every confirmed detection of
/// [listener] becomes a `TriggerKind.wakeWord` event carrying the pre-roll.
final class WakeWordTrigger implements TriggerSource {
  /// Creates the trigger; [clock] stamps the events.
  WakeWordTrigger(this.listener, this.clock);

  /// The listener (started and paused by its owner).
  final WakeWordListener listener;

  /// Time source.
  final Clock clock;

  @override
  Stream<TriggerEvent> get triggers => listener.detections.map(
    (d) => TriggerEvent(
      source: TriggerKind.wakeWord,
      at: clock.now(),
      preRoll: d.preRoll,
    ),
  );
}
