import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/audio_devices_providers.dart';
import '../../l10n/l10n.dart';
import '../../platform/voice/audio_devices.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Choice of microphone and output (WP188, K149): per direction „System“
/// (default) plus the connected devices. A chosen device that is not
/// connected stays listed and marked. Android only (the entry in the
/// settings list is hidden elsewhere).
class AudioScreen extends ConsumerWidget {
  /// Creates the screen.
  const AudioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return SettingsPage(
      title: l.areaAudio,
      intro: l.audioIntro,
      children: [
        _Direction(AudioDirection.input, l.audioInput),
        const SizedBox(height: WSpace.m),
        _Direction(AudioDirection.output, l.audioOutput),
      ],
    );
  }
}

/// Display name of a device type.
String audioTypeLabel(AppLocalizations l, AudioDeviceType type) =>
    switch (type) {
      AudioDeviceType.builtinMic => l.audioTypeBuiltinMic,
      AudioDeviceType.builtinSpeaker => l.audioTypeBuiltinSpeaker,
      AudioDeviceType.earpiece => l.audioTypeEarpiece,
      AudioDeviceType.wiredHeadset => l.audioTypeWiredHeadset,
      AudioDeviceType.usb => l.audioTypeUsb,
      AudioDeviceType.line => l.audioTypeLine,
      AudioDeviceType.bluetoothSco => l.audioTypeBluetoothSco,
      AudioDeviceType.bluetoothA2dp => l.audioTypeBluetoothA2dp,
      AudioDeviceType.bluetoothLe => l.audioTypeBluetoothLe,
      AudioDeviceType.hearingAid => l.audioTypeHearingAid,
      AudioDeviceType.other => l.audioTypeOther,
    };

class _Direction extends ConsumerWidget {
  const _Direction(this.direction, this.title);

  final AudioDirection direction;
  final String title;

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    AudioDevice? device,
  ) async {
    final l = context.l10n;
    try {
      await ref.read(audioSelectionProvider.notifier).select(direction, device);
    } on Object {
      // Not stored: the list still shows the old choice, so say it.
      if (context.mounted) showHint(context, l.audioSaveFailed);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final choice = ref.watch(audioChoiceProvider(direction));
    final connected =
        ref.watch(audioDevicesProvider).value?.of(direction) ?? const [];
    final selected = choice.selected;
    final active = choice.active;
    final ok = CheckStatusIcon(CheckStatus.ok, semanticLabel: l.selected);
    return SettingsSection(
      title: title,
      children: [
        SettingsRow(
          title: active == null
              ? l.audioInUseSystem
              : l.audioInUse(active.name),
        ),
        SettingsRow(
          title: l.audioSystem,
          detail: l.audioSystemDetail,
          onTap: () => unawaited(_select(context, ref, null)),
          trailing: selected == null ? ok : null,
        ),
        if (choice.selectedMissing)
          SettingsRow(
            title: selected!.name,
            detail: '${audioTypeLabel(l, selected.type)} · ${l.audioMissing}',
            onTap: () => unawaited(_select(context, ref, selected)),
            trailing: ok,
          ),
        for (final d in connected)
          SettingsRow(
            title: d.name,
            detail: audioTypeLabel(l, d.type),
            onTap: () => unawaited(_select(context, ref, d)),
            trailing: selected?.key == d.key ? ok : null,
          ),
      ],
    );
  }
}
