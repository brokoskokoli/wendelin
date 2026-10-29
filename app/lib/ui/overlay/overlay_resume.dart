import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_controller.dart';
import '../../di/attestation_hub.dart';
import '../../di/attestation_providers.dart';
import '../../di/providers.dart';
import '../../di/routing.dart';
import '../../voice/voice_controller.dart';

// The request from before goes on after the unlock, answered here and read
// aloud (K85); without one, the overlay listens again.
Future<void> continueAfterUnlock(
  WidgetRef ref,
  LockedPendingRequest? request, {
  required bool Function() alive,
  required void Function() fire,
}) async {
  final voice = ref.read(voiceControllerProvider.notifier);
  if (request != null) {
    final spoken =
        alive() && await answerRemembered(ref, request, voice.answerText);
    if (!spoken && alive()) {
      unawaited(ref.read(agentControllerProvider.notifier).send(request.text));
    }
  } else if (alive() && !requestRunning(ref)) {
    fire();
  }
}

void warmUpOverlayAttestation(WidgetRef ref, bool Function() alive) =>
    scheduleMicrotask(() {
      if (!alive()) return;
      unawaited(
        warmUpAttestation(
          config: ref.read(providerConfigProvider.future),
          network: ref.read(networkStatusProvider),
          hub: ref.read(attestationHubProvider),
        ),
      );
    });

// Recognition, follow-up listening or an answer is under way.
bool requestRunning(WidgetRef ref) =>
    ref.read(voiceControllerProvider).active ||
    ref.read(agentControllerProvider).running;
