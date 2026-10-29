import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../../di/voice_providers.dart';
import '../../../di/wake_providers.dart';
import '../../../di/wake_service.dart';
import '../../../di/wake_settings.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/assistant_platform.dart';
import '../../../platform/wake/wake_platform.dart';
import '../../../platform/wake/wake_stage2_gap.dart';
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
  AppLocalizations l,
  WakeServiceSettings settings,
  WakeServiceStatus status,
) => switch (wakeStateKind(settings, status)) {
  WakeStateKind.off => l.off,
  WakeStateKind.running => l.wakeServiceSectionRunning,
  WakeStateKind.paused =>
    status.pausedUntil != null
        ? l.wakeServiceSectionPausedUntil(_clock(status.pausedUntil!))
        : l.wakeServiceSectionPausedLoading,
  WakeStateKind.killed => wakeStopText(l, status.lastStop),
};

/// Plain German for the log code of the last stop (the status row when the
/// switch is on but the service does not run).
String wakeStopText(AppLocalizations l, String? reason) => switch (reason) {
  'timeout' => l.wakeServiceSectionEndedTimeout,
  'no-role' => l.wakeServiceSectionEndedNoRole,
  'no-permission' => l.wakeServiceSectionEndedNoPermission,
  'engine-failed' => l.wakeServiceSectionEndedEngine,
  'modelMissing' => l.wakeServiceSectionEndedModel,
  'not-charging' || 'unplug' => l.wakeServiceSectionEndedNotCharging,
  'paused' => l.wakeServiceSectionEndedPaused,
  'user-off' || 'disabled' => l.off,
  _ => l.wakeServiceSectionEndedSystem,
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

  void _loadModel() => unawaited(
    ref
        .read(modelStatesProvider.notifier)
        .download(SpeechModelCatalog.wakeClassifierWendelin.id),
  );

  List<Widget> _needModel() => [
    SettingsRow(
      key: const ValueKey('wakeNeedModel'),
      title: context.l10n.wakeServiceSectionNeedModel,
      detail: context.l10n.wakeServiceSectionNeedModelBody,
    ),
    LinkButton(
      context.l10n.wakeServiceSectionLoadModel,
      onPressed: _loadModel,
      external: false,
    ),
  ];

  Widget _soundSection({
    required bool tone,
    required WakeStage2Settings stage2,
  }) => SettingsSection(
    title: context.l10n.wakeServiceSectionSoundCheck,
    children: [
      SettingsRow(
        title: context.l10n.wakeServiceSectionChime,
        detail: context.l10n.wakeServiceSectionChimeDetail,
        trailing: WSwitch(
          value: tone,
          semanticLabel: context.l10n.wakeServiceSectionChime,
          onChanged: (v) =>
              unawaited(ref.read(wakeToneProvider.notifier).set(enabled: v)),
        ),
      ),
      SettingsRow(
        key: const ValueKey('wakeStage2VerifierB'),
        title: context.l10n.wakeServiceSectionVerifierB,
        detail: context.l10n.wakeServiceSectionVerifierBDetail,
        onTap: () => unawaited(
          ref
              .read(wakeStage2Provider.notifier)
              .setVerifierB(enabled: !stage2.verifierB),
        ),
        trailing: stage2.verifierB
            ? CheckStatusIcon(
                CheckStatus.ok,
                semanticLabel: context.l10n.selected,
              )
            : null,
      ),
      SettingsRow(
        key: const ValueKey('wakeStage2Recognizer'),
        title: context.l10n.wakeServiceSectionRecognizer,
        detail: context.l10n.wakeServiceSectionRecognizerDetail,
        onTap: () => unawaited(
          ref
              .read(wakeStage2Provider.notifier)
              .setRecognizer(enabled: !stage2.recognizer),
        ),
        trailing: stage2.recognizer
            ? CheckStatusIcon(
                CheckStatus.ok,
                semanticLabel: context.l10n.selected,
              )
            : null,
      ),
    ],
  );

  Future<void> _chooseRole() async {
    final opened = await ref
        .read(assistantPlatformProvider)
        .openAssistantSettings();
    if (!opened && mounted) {
      showHint(context, context.l10n.wakeServiceSectionSettingsFail);
    }
  }

  Widget _action(String label, VoidCallback onPressed) =>
      LinkButton(label, onPressed: onPressed);

  Widget _enrollLink() => LinkButton(
    context.l10n.wakeServiceSectionToEnroll,
    onPressed: widget.onEnroll,
    external: false,
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
        ? CheckStatusIcon(CheckStatus.ok, semanticLabel: context.l10n.selected)
        : null,
  );

  Widget _whenSection(WakeServiceSettings settings) => SettingsSection(
    title: context.l10n.wakeServiceSectionWhen,
    children: [
      _condition(
        settings,
        WakeCondition.charging,
        context.l10n.wakeServiceSectionOnlyCharging,
        context.l10n.wakeServiceSectionOnlyChargingHint,
      ),
      _condition(
        settings,
        WakeCondition.always,
        context.l10n.wakeServiceSectionAlways,
        context.l10n.wakeServiceSectionAlwaysHint,
      ),
    ],
  );

  Widget _backgroundSection({
    required WakeServiceSettings settings,
    required WakeServiceStatus status,
    required bool noRole,
    required bool noVoice,
    required bool noModel,
    required bool locked,
  }) => SettingsSection(
    title: context.l10n.wakeServiceSectionBackground,
    children: [
      SettingsRow(
        key: const ValueKey('wakeStatus'),
        title: context.l10n.wakeServiceSectionStatus,
        detail: wakeStatusText(context.l10n, settings, status),
      ),
      SettingsRow(
        key: const ValueKey('wakeSwitch'),
        title: context.l10n.wakeServiceSectionEnable,
        detail: context.l10n.wakeServiceSectionEnableDetail,
        trailing: WSwitch(
          value: settings.enabled,
          semanticLabel: context.l10n.wakeServiceSectionEnable,
          onChanged: locked ? null : (v) => unawaited(_toggle(on: v)),
        ),
      ),
      if (noModel && !settings.enabled) ..._needModel(),
      if (noRole) ...[
        SettingsRow(
          key: ValueKey('wakeNeedRole'),
          title: context.l10n.wakeServiceSectionNotAssistant,
          detail: context.l10n.wakeServiceSectionNotAssistantBody,
        ),
        _action(
          context.l10n.wakeServiceSectionChooseAssistant,
          () => unawaited(_chooseRole()),
        ),
      ],
      if (noVoice) ...[
        SettingsRow(
          key: ValueKey('wakeNeedVoice'),
          title: context.l10n.wakeServiceSectionEnrollFirst,
          detail: context.l10n.wakeServiceSectionEnrollFirstBody,
        ),
        _enrollLink(),
      ],
    ],
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
    final stage2 =
        ref.watch(wakeStage2Provider).value ?? const WakeStage2Settings();
    final tone = ref.watch(wakeToneProvider).value ?? true;
    final noRole = !status.holdsRole;
    final noVoice = speakers.isEmpty && ref.watch(wakeNeedsVoiceProvider);
    // WP173: switching on needs the trained model (switching off never
    // does, and an already switched-on service stays on).
    final noModel = !ref.watch(wakeClassifierInstalledProvider);
    final locked = (noRole || noVoice || noModel) && !settings.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.l18,
      children: [
        _backgroundSection(
          settings: settings,
          status: status,
          noRole: noRole,
          noVoice: noVoice,
          noModel: noModel,
          locked: locked,
        ),
        _whenSection(settings),
        _soundSection(tone: tone, stage2: stage2),
        if (settings.enabled || !noRole) const BatteryHints(),
      ],
    );
  }
}
