import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import '../../voice/voice_log.dart';
import 'wake_stage2_gap.dart';

/// Holds the current [WakeStage2Gap] of the wake word host (WP171) and sends
/// every change on (`stage2Gap` to Kotlin, which shows it in the service
/// notification).
final class WakeGapTracker {
  /// Creates the tracker; [check] asks `WakeParts.stage2Gap`, [send] tells
  /// Kotlin the new reason (`null` = none).
  WakeGapTracker({required this.check, required this.send});

  /// Asks whether stage 2 cannot decide right now.
  final Future<WakeStage2Gap?> Function() check;

  /// Sends the reason (`logName`, `null` = none) to Kotlin.
  final Future<void> Function(String? reason) send;

  final _gap = ValueNotifier<WakeStage2Gap?>(null);

  /// Reason why stage 2 could not decide on the last candidate, `null` if it
  /// could (or nothing known yet).
  ValueListenable<WakeStage2Gap?> get gap => _gap;

  /// Sets the gap; only a change is logged and sent.
  void set(WakeStage2Gap? gap) {
    if (_gap.value == gap) return;
    _gap.value = gap;
    voiceLog('wake-gap', {'reason': gap == null ? 'none' : gap.logName});
    unawaited(send(gap?.logName));
  }

  /// Result of a candidate: a decision clears a missing model, but not
  /// `no_sequences` (the recognizer decided because B could not; only
  /// [recheck] after enrolling clears that).
  void onVerdict(WakeStage2Gap? gap) {
    if (gap == null && _gap.value == WakeStage2Gap.noSequences) return;
    set(gap);
  }

  /// Before the first candidate: without a model the notification must say so
  /// at once (the app may not be open). Unknown ([check] throws) claims
  /// nothing. [ending] is asked after the wait.
  Future<void> checkAtStart({
    required bool verify,
    required bool Function() ending,
  }) async {
    WakeStage2Gap? gap;
    if (verify) {
      try {
        gap = await check();
      } on Object {
        gap = null;
      }
    }
    if (ending()) return;
    set(gap);
  }

  /// The app installed or removed a recognition model or enrolled a voice:
  /// asks again. Without a listener there is nothing to tell (the check runs
  /// when it starts); on an error the notice stays as it is.
  Future<void> recheck({
    required bool active,
    required bool Function() ending,
  }) async {
    if (!active || ending()) return;
    WakeStage2Gap? gap;
    try {
      gap = await check();
    } on Object {
      return;
    }
    if (ending()) return;
    set(gap);
  }
}
