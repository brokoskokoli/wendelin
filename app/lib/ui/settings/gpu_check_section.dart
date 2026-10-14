import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_providers/wendelin_providers.dart' show GpuCheckMode;

import '../../di/attestation_providers.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Text of the GPU modes (title, explanation).
(String, String) gpuModeText(GpuCheckMode mode) => switch (mode) {
  GpuCheckMode.off => (
    'Aus',
    'Standard. Wendelin prüft nur lokal, ob die GPU-Nachweise zu deiner '
        'Anfrage gehören. Kein Aufruf an NVIDIA.',
  ),
  GpuCheckMode.before => (
    'Vorher',
    'NVIDIA prüft die GPU-Nachweise, bevor deine Anfrage den Anbieter '
        'erreicht. Schlägt die Prüfung fehl, wird nichts gesendet. Du '
        'kannst dann einmalig ohne GPU-Prüfung senden.',
  ),
  GpuCheckMode.after => (
    'Nachher',
    'Die Prüfung läuft nach der Antwort. Schlägt sie fehl, warnt dich eine '
        'Benachrichtigung, die Antwort wird rot markiert, und die nächsten '
        'Anfragen an dieses Modell prüfen vorher.',
  ),
};

/// „GPU-Prüfung über NVIDIA“: off, before or after the request.
class GpuCheckSection extends ConsumerWidget {
  /// Creates the section.
  const GpuCheckSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(gpuCheckModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.s,
      children: [
        SettingsSection(
          title: 'GPU-Prüfung über NVIDIA',
          children: [
            for (final m in GpuCheckMode.values)
              SettingsRow(
                title: gpuModeText(m).$1,
                detail: gpuModeText(m).$2,
                onTap: () =>
                    unawaited(ref.read(gpuCheckModeProvider.notifier).set(m)),
                trailing: m == mode
                    ? const CheckStatusIcon(
                        CheckStatus.ok,
                        semanticLabel: 'gewählt',
                      )
                    : null,
              ),
          ],
        ),
        Text(
          'Für „Vorher“ und „Nachher“ ruft Wendelin den Dienst von NVIDIA '
          '(nras.attestation.nvidia.com) auf. Gesendet werden nur die '
          'Nachweise der GPU, keine Inhalte deiner Anfragen oder Antworten.',
          style: WText.caption,
        ),
      ],
    );
  }
}
