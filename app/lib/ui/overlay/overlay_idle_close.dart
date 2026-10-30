import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../agent/agent_controller.dart';
import '../../voice/voice_controller.dart';

/// Whether nothing is left to do after listening ended, so the overlay may
/// close itself (WP172, WP182, WP186): no new voice request, no running answer,
/// no active speech output, no pending follow-up window, no pending undo window,
/// no open question or GPU choice, and no unlock offer while locked ([unlocking]:
/// the unlock window is active or open). Typing and an own cancel are the overlay's
/// own state and checked there.
bool nothingLeftToDo(
  WidgetRef ref, {
  required bool locked,
  required bool unlocking,
}) {
  final voice = ref.read(voiceControllerProvider);
  final conversation = ref.read(agentControllerProvider);
  if (voice.active ||
      voice.followUp ||
      conversation.running ||
      conversation.hasPendingUndo ||
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
    required this.onListening,
  });

  final WidgetRef ref;
  final bool Function() enabled;
  final bool Function() typing;
  final bool Function() closing;
  final bool Function() locked;
  final bool Function() unlocking;
  final void Function(String by) close;
  final Duration Function() stopCloseDelay;

  /// Spoken listening (or an answer to a request) begins, however it was
  /// started (trigger, mic tap, unlock).
  final void Function() onListening;

  // Listening ended because of our own retrigger (not the end of a request):
  // no automatic close.
  bool _retriggering = false;

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

  /// Runs [cancel] (our own cancel at a retrigger or undo) without closing.
  /// With [thenRecheck] it decides once [cancel] is completely done (undo:
  /// the spoken confirmation is over), as the end of listening would.
  Future<void> retrigger(
    Future<void> Function() cancel, {
    bool thenRecheck = false,
  }) async {
    _retriggering = true;
    try {
      await cancel();
    } finally {
      _retriggering = false;
    }
    if (thenRecheck) recheck();
  }

  /// An undo (cancels output, speaks the confirmation): no close meanwhile,
  /// afterwards it decides like at the end of listening.
  Future<void> afterUndo(Future<Object?> Function() undo) =>
      retrigger(() async => undo(), thenRecheck: true);

  /// Call from `build`. Not `active`: `preparing` ends before the phase turns
  /// to listening, that gap is no end of listening (closing there kills the
  /// start).
  void listen() {
    ref.listen(
      voiceControllerProvider.select(
        (v) => v.phase != VoiceState.idle || v.awaitingAnswer,
      ),
      (was, now) {
        if (now) {
          cancelClose(); // listening again: no pending stop/error close
          onListening();
        }
        // Decide after the other reactions of the same moment (stop word,
        // unlock offer) set their blockers: idle is reported before them.
        if (was == true && !now) scheduleMicrotask(recheck);
      },
    );
    // WP182: Recheck after speech output ends.
    ref.listen(voiceControllerProvider.select((v) => v.speaking), (was, now) {
      if (was == true && !now) scheduleMicrotask(recheck);
    });
    // WP186: Recheck after the conversation follow-up window ends.
    ref.listen(voiceControllerProvider.select((v) => v.followUp), (was, now) {
      if (was == true && !now) scheduleMicrotask(recheck);
    });
    // WP182: Recheck after an undo window expires or is resolved.
    ref.listen(agentControllerProvider.select((c) => c.hasPendingUndo), (
      was,
      now,
    ) {
      if (was == true && !now) scheduleMicrotask(recheck);
    });
  }

  /// Decides now, as at the end of listening (also after the keyboard was
  /// closed again without sending).
  void recheck() {
    if (!enabled() || typing()) {
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
