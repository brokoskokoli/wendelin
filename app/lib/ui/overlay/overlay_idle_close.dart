import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../agent/agent_controller.dart';
import '../../voice/voice_controller.dart';

/// Whether nothing is left to do after listening ended, so the overlay may
/// close itself (WP172): no new voice request, no running answer, no open
/// question or GPU choice, and no unlock offer while locked ([unlocking]:
/// the unlock window is active or open). Typing and an own cancel are the
/// overlay's own state and checked there.
bool nothingLeftToDo(
  WidgetRef ref, {
  required bool locked,
  required bool unlocking,
}) {
  final conversation = ref.read(agentControllerProvider);
  if (ref.read(voiceControllerProvider).active ||
      conversation.running ||
      conversation.pending != null ||
      conversation.gpuBlock != null) {
    return false;
  }
  return !(locked && (ref.read(lockedPendingProvider) != null || unlocking));
}

/// Closes the overlay when listening ended and nothing is left to do
/// (WP172). Decided only at the moment listening ends; a blocker that falls
/// away later does not close (a typed exchange keeps its sheet; an unlock
/// starts listening again by itself).
class IdleCloser {
  IdleCloser({
    required this.ref,
    required this.enabled,
    required this.typing,
    required this.closing,
    required this.locked,
    required this.unlocking,
    required this.close,
    required this.stopCloseDelay,
  });

  final WidgetRef ref;
  final bool Function() enabled;
  final bool Function() typing;
  final bool Function() closing;
  final bool Function() locked;
  final bool Function() unlocking;
  final void Function(String by) close;
  final Duration Function() stopCloseDelay;

  // Listening ended because of our own retrigger (not the end of a request)
  // or because the user tapped the microphone off: no automatic close.
  bool _retriggering = false;
  bool _micCancelled = false;

  // A stop or error message is shown; this timer closes after it.
  Timer? _closeTimer;

  /// Closes after [delay] (the stop or error message stays visible meanwhile).
  void closeLater(String by, Duration delay) {
    cancelClose();
    _closeTimer = Timer(delay, () => close(by));
  }

  /// Drops a pending delayed close.
  void cancelClose() => _closeTimer?.cancel();

  /// Disposes the timer.
  void dispose() => cancelClose();

  /// The user tapped the microphone off.
  void micCancelled() => _micCancelled = true;

  /// Runs [cancel] (our own cancel at a retrigger or undo) without closing.
  Future<void> retrigger(Future<void> Function() cancel) async {
    _retriggering = true;
    try {
      await cancel();
    } finally {
      _retriggering = false;
    }
  }

  /// Call from `build`. Not `active`: `preparing` ends before the phase turns
  /// to listening, that gap is no end of listening (closing there kills the
  /// start).
  void listen() {
    ref.listen(
      voiceControllerProvider.select(
        (v) => v.phase != VoiceState.idle || v.awaitingAnswer,
      ),
      (was, now) {
        if (now) _micCancelled = false;
        // Decide after the other reactions of the same moment (stop word,
        // unlock offer) set their blockers: idle is reported before them.
        if (was == true && !now) scheduleMicrotask(_onListeningEnded);
      },
    );
  }

  void _onListeningEnded() {
    if (!enabled() || typing() || _micCancelled) {
      return;
    }
    if (closing() || _retriggering || (_closeTimer?.isActive ?? false)) return;
    if (!nothingLeftToDo(ref, locked: locked(), unlocking: unlocking())) {
      return;
    }
    // An error stays visible briefly, like the stop message.
    if (ref.read(voiceControllerProvider).error != null) {
      closeLater('idle-error', stopCloseDelay());
    } else {
      close('idle');
    }
  }
}
