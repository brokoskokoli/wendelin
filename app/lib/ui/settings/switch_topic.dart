import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_controller.dart';
import '../../agent/chat_entry.dart';
import 'settings_page.dart';

/// Whether the visible conversation holds more than the session marker.
bool conversationHasHistory(WidgetRef ref) => ref
    .read(agentControllerProvider)
    .entries
    .any((e) => e is! SessionStartEntry);

/// A model or profile is changed by hand (WP78): a non-empty conversation
/// then ends and a new one begins, after a short confirmation. Returns
/// `false` if the user declined (the caller then must not switch). „Nochmal
/// mit X“ and routing rules never go through here: they keep the history.
Future<bool> confirmManualModelSwitch(
  BuildContext context,
  WidgetRef ref,
) async {
  final controller = ref.read(agentControllerProvider.notifier);
  if (!conversationHasHistory(ref) ||
      ref.read(agentControllerProvider).running) {
    return true;
  }
  final ok = await confirm(
    context,
    title: 'Neues Gespräch beginnen?',
    message:
        'Beim Wechsel des Modells beginnt ein neues Gespräch. Der aktuelle '
        'Verlauf wird beendet (im Verlauf bleibt er abrufbar).',
    yes: 'Wechseln',
    no: 'Abbrechen',
  );
  if (!ok) return false;
  await controller.newTopic();
  return true;
}
