import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/attestation_providers.dart';
import '../../../di/core_providers.dart';
import '../../../di/voice_providers.dart';
import '../../../di/wake_service.dart';
import '../../../di/wake_settings.dart';
import '../../../platform/battery_platform.dart';
import '../../design/design.dart';
import '../../voice/microphone_access.dart';
import '../battery_hints.dart';
import '../settings_page.dart';

/// Points the user has to know before the wake word listens permanently.
const wakeExplainPoints = [
  (
    'Dauerhafte Benachrichtigung',
    'Solange Wendelin zuhört, zeigt Android eine Benachrichtigung. Ab '
        'Android 14 kannst du sie wegwischen, der Dienst läuft dann weiter. '
        'Ohne die Berechtigung für Benachrichtigungen zeigt Android keine; '
        'Wendelin hört trotzdem zu.',
  ),
  (
    'Mikrofon-Punkt',
    'Android zeigt den grünen Punkt für das Mikrofon, solange der Dienst '
        'zuhört.',
  ),
  (
    'Zuhören bleibt auf dem Gerät',
    'Die Erkennung des Wortes läuft auf dem Gerät. Was du nach „Wendelin“ '
        'sagst, wird als Text an den gewählten KI-Anbieter geschickt. Audio '
        'wird weder gesendet noch gespeichert.',
  ),
  (
    'Akku',
    'Das ständige Zuhören kostet Akku. Standard ist deshalb „Nur beim '
        'Laden“.',
  ),
];

/// Explanation before the first switch-on. `true` = the user agrees.
Future<bool> showWakeExplanation(
  BuildContext context, {
  String? vendorHint,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WColors.surface,
        title: Text('Aktivierungswort einschalten?', style: WText.label),
        content: SingleChildScrollView(
          child: Column(
            key: const ValueKey('wakeExplain'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (title, text) in wakeExplainPoints) ...[
                Text(title, style: WText.label),
                Text(text, style: WText.intro),
                const SizedBox(height: WSpace.s),
              ],
              if (vendorHint != null) Text(vendorHint, style: WText.caption),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Einschalten'),
          ),
        ],
      ),
    ) ??
    false;

/// Switches the wake word on: explains it (once), asks for the microphone
/// and notification permission, switches the service on and offers the
/// exemption from battery optimization. `true` if it is on afterwards.
Future<bool> enableWakeWord(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(storageProvider).settings;
  final explained = await settings.get(wakeExplainedKey) ?? false;
  final battery = await ref.read(batteryStatusProvider.future);
  if (!context.mounted) return false;
  if (!explained) {
    final checklist = vendorChecklists[battery.vendor];
    final ok = await showWakeExplanation(
      context,
      vendorHint: checklist == null ? null : '${checklist.$1}: ${checklist.$2}',
    );
    if (!ok || !context.mounted) return false;
  }
  if (!await ensureMicrophoneAccess(context, ref.read(microphoneProvider))) {
    return false;
  }
  final notifier = ref.read(attestationNotifierProvider);
  if (!await notifier.hasPermission()) await notifier.requestPermission();
  final on = await ref
      .read(wakeServiceProvider.notifier)
      .setEnabled(enabled: true);
  if (!on) return false;
  await settings.set(wakeExplainedKey, true);
  ref.invalidate(wakeStatusProvider);
  if (!battery.ignoringOptimizations && context.mounted) {
    final yes = await confirm(
      context,
      title: 'Akku-Optimierung ausnehmen?',
      message:
          'Damit Android den Dienst nicht beendet, sollte Wendelin von der '
          'Akku-Optimierung ausgenommen sein.',
      yes: 'Ausnehmen',
      no: 'Später',
    );
    if (yes) {
      unawaited(ref.read(batteryPlatformProvider).requestIgnoreOptimizations());
    }
  }
  return true;
}
