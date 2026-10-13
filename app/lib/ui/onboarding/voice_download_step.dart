import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/voice_providers.dart';
import '../../platform/voice/model_installer.dart';
import '../design/design.dart';
import '../settings/model_download_row.dart';
import '../settings/settings_page.dart';

/// Onboarding step „Spracherkennung laden“ (concept: Onboarding): loads
/// the chosen Whisper model plus Silero VAD. Can be skipped; the download
/// continues in the background and can be finished in Einstellungen →
/// Sprache.
class VoiceDownloadStep extends ConsumerStatefulWidget {
  /// Creates the step; [onNext] goes to the next step.
  const VoiceDownloadStep({super.key, required this.onNext});

  /// Next onboarding step.
  final VoidCallback onNext;

  @override
  ConsumerState<VoiceDownloadStep> createState() => _VoiceDownloadState();
}

class _VoiceDownloadState extends ConsumerState<VoiceDownloadStep> {
  @override
  void initState() {
    super.initState();
    // A download interrupted by closing the app continues here.
    unawaited(
      Future(() => ref.read(modelStatesProvider.notifier).resumePartial()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(voiceSettingsProvider).value ?? const VoiceSettings();
    final catalog = ref.watch(speechModelCatalogProvider);
    final states = ref.watch(modelStatesProvider);
    final whisper =
        catalog.byId(settings.sttModel) ?? SpeechModelCatalog.whisperBase;
    const vad = SpeechModelCatalog.sileroVad;
    final needed = [whisper, vad];
    ModelPhase phase(SpeechModel m) =>
        states[m.id]?.phase ?? ModelPhase.unknown;
    final done = needed.every((m) => phase(m) == ModelPhase.installed);
    final busy = needed.any((m) => states[m.id]?.busy ?? false);
    final total = needed.fold(0, (n, m) => n + m.sizeBytes);

    return SettingsPage(
      title: 'Spracherkennung laden',
      showBack: false,
      intro:
          'Wendelin erkennt Sprache auf dem Gerät, ohne Internet und ohne '
          'Google. Dafür lädt er einmal das Whisper-Modell '
          '(${megabytes(total)}, am besten im WLAN).',
      children: [
        SectionCard(
          children: [
            for (final m in catalog.ofKind(SpeechModelKind.stt))
              ModelDownloadRow(
                model: m,
                selected: m.id == whisper.id,
                deletable: false,
                onSelect: () => unawaited(
                  ref
                      .read(voiceSettingsProvider.notifier)
                      .change((s) => s.copyWith(sttModel: m.id)),
                ),
              ),
            const ModelDownloadRow(model: vad, deletable: false),
          ],
        ),
        Text(
          '„base“ ist schnell, „small“ erkennt Deutsch und Französisch '
          'deutlich besser, braucht aber mehr Platz und Zeit.',
          style: WText.caption,
        ),
        if (done)
          PrimaryButton('Weiter', onPressed: widget.onNext)
        else ...[
          PrimaryButton(
            busy ? 'Lädt …' : 'Laden',
            onPressed: busy
                ? null
                : () {
                    final n = ref.read(modelStatesProvider.notifier);
                    for (final m in needed) {
                      if (phase(m) != ModelPhase.installed) {
                        unawaited(n.download(m.id));
                      }
                    }
                  },
          ),
          WideButton(
            busy ? 'Im Hintergrund weiterladen' : 'Später',
            onPressed: widget.onNext,
          ),
        ],
      ],
    );
  }
}
