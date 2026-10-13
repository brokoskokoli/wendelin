import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../agent/agent_controller.dart';
import '../../agent/conversation_state.dart';
import '../../di/providers.dart';
import '../../voice/voice_controller.dart';
import 'confirmation_sheet.dart';

/// Opens the confirmation sheet for [question] (provider, privacy level and
/// risk of the pending tool call); `true` = approved, `null` = dismissed.
Future<bool?> showQuestionSheet(
  BuildContext context,
  WidgetRef ref,
  PendingQuestion question,
) {
  final config = ref.read(providerConfigProvider).value;
  final active = config?.targetFor(
    ref.read(agentControllerProvider).activeProfileId,
  );
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (_) => Consumer(
      builder: (context, ref, _) => ConfirmationSheet(
        question: question,
        providerName: active == null ? '' : config!.nameOf(active.profileId),
        privacy: active?.privacy ?? PrivacyLevel.standard,
        privateSince: ref.watch(
          agentControllerProvider.select((s) => s.privateSince),
        ),
        privateByRequest: ref.watch(
          agentControllerProvider.select((s) => s.privateByRequest),
        ),
        toolRisk: question is ToolQuestion
            ? question.event.risk
            : RiskLevel.external,
        // A voice request also takes a spoken „ja“/„nein“.
        hint: ref.watch(voiceControllerProvider.select((v) => v.answersByVoice))
            ? ConfirmationHint.voice
            : ConfirmationHint.tap,
      ),
    ),
  );
}
