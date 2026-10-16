import 'dart:async';

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
  if (!conversationHasHistory(ref)) return true;
  final running = ref.read(agentControllerProvider).running;
  final ok = await confirm(
    context,
    title: 'Neues Gespräch beginnen?',
    message: running
        ? 'Beim Wechsel des Modells beginnt ein neues Gespräch. Die laufende '
              'Antwort wird abgebrochen und der aktuelle Verlauf beendet (im '
              'Verlauf bleibt er abrufbar).'
        : 'Beim Wechsel des Modells beginnt ein neues Gespräch. Der aktuelle '
              'Verlauf wird beendet (im Verlauf bleibt er abrufbar).',
    yes: 'Wechseln',
    no: 'Abbrechen',
  );
  if (!ok) return false;
  if (ref.read(agentControllerProvider).running) {
    // A running answer first ends; only then can the topic be renewed.
    final done = Completer<void>();
    final sub = ref.listenManual(agentControllerProvider, (_, next) {
      if (!next.running && !done.isCompleted) done.complete();
    });
    controller.cancel();
    if (ref.read(agentControllerProvider).running) {
      await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
    }
    sub.close();
    if (ref.read(agentControllerProvider).running) return false;
  }
  await controller.newTopic();
  return true;
}
