import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/setup_status.dart';
import '../../di/setup_wizard.dart';
import '../../di/voice_providers.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import '../settings/model_download_row.dart';
import '../settings/settings_page.dart';
import 'download_plan.dart';

/// Page 3 of the setup wizard (WP174, required): the recognition model and
/// Silero VAD. A selection field picks the model (default Parakeet; only
/// the catalog's supported ones), „Herunterladen“ fetches it together with
/// Silero VAD, each model row shows its own progress, error and
/// continue/cancel. „Weiter“ is active only when both are installed (the
/// live state, unknown counts as not installed).
class SetupSpeechPage extends ConsumerStatefulWidget {
  /// Creates the page; [onNext] goes on.
  const SetupSpeechPage({super.key, required this.onNext});

  /// Goes on (the wizard checks the state again).
  final VoidCallback onNext;

  @override
  ConsumerState<SetupSpeechPage> createState() => _SetupSpeechState();
}

class _SetupSpeechState extends ConsumerState<SetupSpeechPage> {
  bool _defaulted = false;

  @override
  void initState() {
    super.initState();
    // A download interrupted by closing the app continues here.
    unawaited(
      Future(() => ref.read(modelStatesProvider.notifier).resumePartial()),
    );
  }

  /// The stored model is the settings default (Whisper small) and nothing
  /// of it is on the device: the wizard suggests Parakeet instead, once.
  void _suggestDefault(VoiceSettings settings, ModelState state) {
    if (_defaulted || state.phase == ModelPhase.unknown) return;
    _defaulted = true;
    if (settings.sttModel != const VoiceSettings().sttModel ||
        state.phase != ModelPhase.absent) {
      return;
    }
    unawaited(_choose(SpeechModelCatalog.parakeetV3.id));
  }

  Future<void> _choose(String id) => ref
      .read(voiceSettingsProvider.notifier)
      .change((s) => s.copyWith(sttModel: id));

  void _load(DownloadPlan plan) {
    final n = ref.read(modelStatesProvider.notifier);
    for (final m in plan.missing) {
      unawaited(n.download(m.id));
    }
  }

  Widget _status(DownloadPlan plan) => StatusCard(
    key: const ValueKey('downloadStatus'),
    status: plan.ready
        ? CheckStatus.ok
        : plan.error != null && !plan.busy
        ? CheckStatus.failed
        : CheckStatus.pending,
    title: plan.status(context.l10n),
    detail: plan.ready
        ? null
        : plan.busy
        ? context.l10n.voiceDownloadLoadingPercent(
            '${(plan.progress * 100).floor()}',
          )
        : plan.error,
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final settings = ref.watch(voiceSettingsProvider).value;
    final catalog = ref.watch(speechModelCatalogProvider);
    final states = ref.watch(modelStatesProvider);
    final models = catalog.ofKind(SpeechModelKind.stt);
    final chosen =
        catalog.byId(settings?.sttModel ?? '') ?? SpeechModelCatalog.parakeetV3;
    if (settings != null) {
      _suggestDefault(
        settings,
        states[chosen.id] ?? const ModelState(ModelPhase.unknown),
      );
    }
    const vad = SpeechModelCatalog.sileroVad;
    final plan = DownloadPlan.of([chosen, vad], states);
    final facts = ref.watch(setupFactsProvider);
    // „Weiter“ follows the live state of the wizard, not only the plan.
    final canGoOn = plan.ready && facts.canAdvance(SetupPage.speech);
    return SettingsPage(
      title: l.setupSpeechTitle,
      intro: l.setupSpeechIntro,
      children: [
        SectionCard(
          children: [
            SettingsRow(
              title: l.setupSpeechModel,
              trailing: PopupMenuButton<String>(
                key: const ValueKey('sttModelPicker'),
                enabled: !plan.busy,
                tooltip: l.setupSpeechModel,
                initialValue: chosen.id,
                onSelected: (id) => unawaited(_choose(id)),
                itemBuilder: (_) => [
                  for (final m in models)
                    PopupMenuItem(value: m.id, child: Text(shortModelName(m))),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(shortModelName(chosen), style: WText.body),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
            ModelDownloadRow(model: chosen, deletable: false),
            const ModelDownloadRow(model: vad, deletable: false),
          ],
        ),
        _status(plan),
        if (canGoOn)
          PrimaryButton(l.next, onPressed: widget.onNext)
        else ...[
          PrimaryButton(
            plan.loadLabel(l),
            onPressed: plan.canLoad ? () => _load(plan) : null,
          ),
          WideButton(l.next, onPressed: null),
        ],
      ],
    );
  }
}
