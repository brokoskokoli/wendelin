import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/attestation_providers.dart';
import '../../../di/core_providers.dart';
import '../../../di/voice_providers.dart';
import '../../../di/wake_service.dart';
import '../../../di/wake_settings.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/battery_platform.dart';
import '../../design/design.dart';
import '../../voice/microphone_access.dart';
import '../battery_hints.dart';
import '../settings_page.dart';

/// Points the user has to know before the wake word listens permanently.
List<(String, String)> wakeExplainPoints(AppLocalizations l) => [
  (l.wakeExplainPersistentTitle, l.wakeExplainPersistentBody),
  (l.wakeExplainMicDotTitle, l.wakeExplainMicDotBody),
  (l.wakeExplainLocalTitle, l.wakeExplainLocalBody),
  (l.wakeExplainBatteryTitle, l.wakeExplainBatteryBody),
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
        title: Text(context.l10n.wakeExplainEnableTitle, style: WText.label),
        content: SingleChildScrollView(
          child: Column(
            key: const ValueKey('wakeExplain'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (title, text) in wakeExplainPoints(context.l10n)) ...[
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
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.wakeExplainEnable),
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
    final checklist = vendorChecklists(context.l10n)[battery.vendor];
    final ok = await showWakeExplanation(
      context,
      vendorHint: checklist == null
          ? null
          : context.l10n.wakeExplainChecklist(checklist.$1, checklist.$2),
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
  if (!on) {
    // The page showed the model as installed, the disk says otherwise (or it
    // cannot be read): say so, and read the model states again.
    unawaited(ref.read(modelStatesProvider.notifier).refresh());
    if (context.mounted) {
      showHint(context, context.l10n.wakeServiceSectionNeedModelBody);
    }
    return false;
  }
  await settings.set(wakeExplainedKey, true);
  ref.invalidate(wakeStatusProvider);
  if (!battery.ignoringOptimizations && context.mounted) {
    final yes = await confirm(
      context,
      title: context.l10n.wakeExplainBatteryExemptTitle,
      message: context.l10n.wakeExplainBatteryExemptBody,
      yes: context.l10n.wakeExplainExempt,
      no: context.l10n.later,
    );
    if (yes) {
      unawaited(ref.read(batteryPlatformProvider).requestIgnoreOptimizations());
    }
  }
  return true;
}
