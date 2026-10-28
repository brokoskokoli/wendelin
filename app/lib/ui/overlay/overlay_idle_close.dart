import 'package:flutter_riverpod/flutter_riverpod.dart';

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
