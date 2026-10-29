import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/core_providers.dart';
import '../../di/setup_status.dart';
import '../../di/setup_wizard.dart';
import '../../di/voice_providers.dart';
import '../../l10n/l10n.dart';
import '../../platform/device_memory.dart';
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

  /// Nothing is stored yet and the default model is not on the device: the
  /// wizard suggests Parakeet (Whisper base on a device with little RAM),
  /// once, and stores it.
  Future<void> _suggestDefault(ModelState state) async {
    if (_defaulted || state.phase != ModelPhase.absent) return;
    _defaulted = true;
    // Only while nothing is stored: a model chosen on purpose (stored once
    // the wizard or the settings changed it) is never overridden.
    final stored = await ref
        .read(storageProvider)
        .settings
        .get(voiceSettingsKey);
    if (stored != null || !mounted) return;
    final memory = await ref.read(deviceMemoryProvider.future);
    await _choose(
      isLowMemory(memory)
          ? SpeechModelCatalog.whisperBase.id
          : SpeechModelCatalog.parakeetV3.id,
    );
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
        : null, // the failure text is shown in the model's row only
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
      unawaited(
        _suggestDefault(
          states[chosen.id] ?? const ModelState(ModelPhase.unknown),
        ),
      );
    }
    final memory = ref.watch(deviceMemoryProvider).value;
    final lowMemory = isLowMemory(memory)
        ? decimal1(l, memory! / (1024 * 1024 * 1024))
        : null;
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
        if (lowMemory != null && chosen.id == SpeechModelCatalog.whisperBase.id)
          Text(l.setupSpeechLowMemory(lowMemory), style: WText.caption),
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
