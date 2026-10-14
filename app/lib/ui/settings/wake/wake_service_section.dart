import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/wake_providers.dart';
import '../../../di/wake_service.dart';
import '../../../di/wake_settings.dart';
import '../../../platform/assistant_platform.dart';
import '../../../platform/wake/wake_platform.dart';
import '../../design/design.dart';
import '../battery_hints.dart';
import '../settings_page.dart';
import 'wake_explain.dart';

/// What the status line says.
enum WakeStateKind {
  /// Switched off.
  off,

  /// Listens.
  running,

  /// Waits (pause, or only while charging and not charging).
  paused,

  /// Switched on but not running: Android ended it.
  killed,
}

/// Derives the state shown from the switch and the service status.
WakeStateKind wakeStateKind(
  WakeServiceSettings settings,
  WakeServiceStatus status,
) {
  if (!settings.enabled) return WakeStateKind.off;
  if (status.running && status.pausedUntil == null) {
    return WakeStateKind.running;
  }
  if (status.pausedUntil != null ||
      (settings.condition == WakeCondition.charging && !status.charging)) {
    return WakeStateKind.paused;
  }
  return WakeStateKind.killed;
}

String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

/// Text of the status row.
String wakeStatusText(
  WakeServiceSettings settings,
  WakeServiceStatus status,
) => switch (wakeStateKind(settings, status)) {
  WakeStateKind.off => 'Aus',
  WakeStateKind.running => 'Läuft',
  WakeStateKind.paused =>
    status.pausedUntil != null
        ? 'Pausiert bis ${_clock(status.pausedUntil!)}'
        : 'Pausiert: wartet auf das Laden',
  WakeStateKind.killed =>
    'Vom System beendet'
        '${status.lastStop == null ? '' : ' (letzter Grund: ${status.lastStop})'}',
};

/// Settings → Aktivierungswort, top part (WP50 b): switch (locked without
/// assistant role or learned voice), condition, confirmation tone, second
/// stage and the battery hints of WP56.
///
/// There is no „Empfindlichkeit“: the engine has one threshold per learned
/// voice, set by enrolling and calibrating (WP60), and no global offset.
class WakeServiceSection extends ConsumerStatefulWidget {
  /// Creates the section; [onEnroll] starts the enrollment.
  const WakeServiceSection({super.key, required this.onEnroll});

  /// Leads to the enrollment („Stimme einlernen“).
  final VoidCallback onEnroll;

  @override
  ConsumerState<WakeServiceSection> createState() => _State();
}

class _State extends ConsumerState<WakeServiceSection> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back from the role dialog or the battery settings: ask again.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref
        ..invalidate(wakeStatusProvider)
        ..invalidate(batteryStatusProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _toggle({required bool on}) async {
    if (on) {
      await enableWakeWord(context, ref);
    } else {
      await ref.read(wakeServiceProvider.notifier).setEnabled(enabled: false);
    }
    ref.invalidate(wakeStatusProvider);
  }

  Future<void> _chooseRole() async {
    final opened = await ref
        .read(assistantPlatformProvider)
        .openAssistantSettings();
    if (!opened && mounted) {
      showHint(context, 'Die Systemeinstellungen ließen sich nicht öffnen.');
    }
  }

  Widget _action(String label, VoidCallback onPressed) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: WColors.link,
        minimumSize: const Size(WSize.touchMin, WSize.touchMin),
      ),
      child: Text(label),
    ),
  );

  Widget _condition(
    WakeServiceSettings settings,
    WakeCondition value,
    String title,
    String detail,
  ) => SettingsRow(
    key: ValueKey('wakeCondition.${value.name}'),
    title: title,
    detail: detail,
    onTap: () =>
        unawaited(ref.read(wakeServiceProvider.notifier).setCondition(value)),
    trailing: settings.condition == value
        ? const CheckStatusIcon(CheckStatus.ok, semanticLabel: 'gewählt')
        : null,
  );

  @override
  Widget build(BuildContext context) {
    // „Aus“ from the notification: the switch follows.
    ref.listen(wakeStatusProvider, (_, next) {
      final status = next.value;
      if (status != null) {
        unawaited(ref.read(wakeServiceProvider.notifier).adoptStatus(status));
      }
    });
    final settings = ref.watch(wakeServiceProvider).value;
    final status = ref.watch(wakeStatusProvider).value;
    if (settings == null || status == null) return const SizedBox.shrink();
    final speakers = ref.watch(wakeSpeakersProvider).value ?? const [];
    final verify = ref.watch(wakeVerifyProvider).value ?? true;
    final tone = ref.watch(wakeToneProvider).value ?? true;
    final noRole = !status.holdsRole;
    final noVoice = speakers.isEmpty;
    final locked = (noRole || noVoice) && !settings.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          title: 'Zuhören im Hintergrund',
          children: [
            SettingsRow(
              key: const ValueKey('wakeStatus'),
              title: 'Status',
              detail: wakeStatusText(settings, status),
            ),
            SettingsRow(
              key: const ValueKey('wakeSwitch'),
              title: 'Aktivierungswort einschalten',
              detail: 'Wendelin hört im Hintergrund auf „Wendelin“.',
              trailing: WSwitch(
                value: settings.enabled,
                semanticLabel: 'Aktivierungswort einschalten',
                onChanged: locked ? null : (v) => unawaited(_toggle(on: v)),
              ),
            ),
            if (noRole) ...[
              const SettingsRow(
                key: ValueKey('wakeNeedRole'),
                title: 'Wendelin ist nicht dein Assistent',
                detail:
                    'Android erlaubt das Zuhören im Hintergrund nur dem '
                    'Standard-Assistenten. Wähle Wendelin als Assistenten.',
              ),
              _action('Assistenten wählen', () => unawaited(_chooseRole())),
            ],
            if (noVoice) ...[
              const SettingsRow(
                key: ValueKey('wakeNeedVoice'),
                title: 'Erst Stimme einlernen',
                detail:
                    'Ohne eingelernte Stimme erkennt Wendelin das '
                    'Aktivierungswort nicht.',
              ),
              _action('Zum Einlernen', widget.onEnroll),
            ],
          ],
        ),
        SettingsSection(
          title: 'Wann zuhören?',
          children: [
            _condition(
              settings,
              WakeCondition.charging,
              'Nur beim Laden',
              'Schont den Akku (Standard).',
            ),
            _condition(
              settings,
              WakeCondition.always,
              'Immer',
              'Kostet spürbar Akku.',
            ),
          ],
        ),
        SettingsSection(
          title: 'Ton und Prüfung',
          children: [
            SettingsRow(
              title: 'Bestätigungston',
              detail: 'Ein kurzer Ton, wenn Wendelin das Wort erkannt hat.',
              trailing: WSwitch(
                value: tone,
                semanticLabel: 'Bestätigungston',
                onChanged: (v) => unawaited(
                  ref.read(wakeToneProvider.notifier).set(enabled: v),
                ),
              ),
            ),
            SettingsRow(
              title: 'Nachprüfung mit Whisper',
              detail:
                  'Wendelin hört nur zu, wenn Whisper „Wendelin“ bestätigt. '
                  'Schalte es aus, wenn es mit deiner Stimme zu streng ist; '
                  'dann gibt es mehr Fehlauslösungen.',
              trailing: WSwitch(
                value: verify,
                semanticLabel: 'Nachprüfung mit Whisper',
                onChanged: (v) => unawaited(
                  ref.read(wakeVerifyProvider.notifier).set(enabled: v),
                ),
              ),
            ),
          ],
        ),
        if (settings.enabled || !noRole) const BatteryHints(),
      ],
    );
  }
}
