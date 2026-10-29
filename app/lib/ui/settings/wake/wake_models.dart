import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../../di/voice_providers.dart';
import '../../../di/wake_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/wake/wake_stage2_gap.dart';
import '../../../voice/wake/wake_storage.dart';
import '../../design/design.dart';
import '../settings_page.dart';

/// Models that enrolling, calibrating and trying out the wake word need
/// but that are not loaded yet (WP65): only the wake features. Whisper is
/// not used by these flows (see [wakeVerifyMissingProvider]). Empty when
/// everything is there.
final wakeMissingModelsProvider = Provider<List<SpeechModel>>((ref) {
  final catalog = ref.watch(speechModelCatalogProvider);
  final states = ref.watch(modelStatesProvider);
  final m = catalog.byId(SpeechModelCatalog.wakeFeatures.id);
  return [if (m != null && states[m.id]?.phase != ModelPhase.installed) m];
});

/// Whisper (the chosen size) while the re-check with Whisper is on but the
/// model is not loaded: only an optional hint when trying out, never a
/// blocker.
final wakeVerifyMissingProvider = Provider<List<SpeechModel>>((ref) {
  final catalog = ref.watch(speechModelCatalogProvider);
  final states = ref.watch(modelStatesProvider);
  final verify = ref.watch(wakeVerifyProvider).value ?? true;
  final sttId = ref.watch(voiceSettingsProvider).value?.sttModel;
  if (!verify || sttId == null) return const [];
  final m = catalog.byId(sttId);
  return [if (m != null && states[m.id]?.phase != ModelPhase.installed) m];
});

/// The learned voices with embeddings and their templates.
final _wakeVoicesProvider = Provider<List<(WakeSpeaker, WakeTemplates)>>((ref) {
  final speakers = ref.watch(wakeSpeakersProvider).value ?? const [];
  return [
    for (final s in speakers)
      if (ref.watch(wakeTemplatesProvider(s.id)).value case final t?)
        if (t.embeddings.isNotEmpty) (s, t),
  ];
});

/// WP171: the voice that needs enrolling again for verifier B (the first
/// one without sequences), `null` if every voice has them.
final wakeSpeakerWithoutSequencesProvider = Provider<WakeSpeaker?>((ref) {
  for (final (s, t) in ref.watch(_wakeVoicesProvider)) {
    if (!t.hasSequences) return s;
  }
  return null;
});

/// WP171: why stage 2 cannot decide (rule: [wakeStage2GapOf], the same as in
/// the engine). A learned voice without sequences for verifier B and no
/// recognizer installed: `modelMissing`; with a recognizer: `noSequences`
/// (only the recognizer decides, enroll again). `null` while the install
/// states are not read yet (no flash of the notice at start).
final wakeStage2GapProvider = Provider<WakeStage2Gap?>((ref) {
  final sets = ref.watch(_wakeVoicesProvider).map((v) => v.$2).toList();
  final installed = wakeStage2RecognizerInstalled(
    ref.watch(modelStatesProvider),
  );
  if (installed == null) return null;
  final stage2 =
      ref.watch(wakeStage2Provider).value ?? const WakeStage2Settings();
  return wakeStage2GapOf(
    anyVoice: sets.isNotEmpty,
    anyWithoutSequences: sets.any((t) => !t.hasSequences),
    verifierB: stage2.verifierB && !wakeVerifierBMuIsPlaceholder,
    recognizer: stage2.recognizer,
    recognizerInstalled: installed,
  );
});

/// WP171: notice for [wakeStage2GapProvider]. Missing model: button
/// downloads Parakeet through the model management; missing sequences: the
/// button enrolls the wake word again ([onEnroll]).
class WakeStage2GapNotice extends ConsumerWidget {
  /// Creates the notice; [onEnroll] starts the enrollment again.
  const WakeStage2GapNotice({super.key, this.onEnroll});

  /// Starts enrolling again (hint `noSequences`).
  final VoidCallback? onEnroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gap = ref.watch(wakeStage2GapProvider);
    if (gap == null) return const SizedBox.shrink();
    final id = SpeechModelCatalog.parakeetV3.id;
    final phase = ref.watch(modelStatesProvider.select((s) => s[id]?.phase));
    final loading =
        phase == ModelPhase.downloading || phase == ModelPhase.unpacking;
    final l = context.l10n;
    final missing = gap == WakeStage2Gap.modelMissing;
    return Column(
      key: ValueKey(missing ? 'wakeStage2Gap' : 'wakeStage2NoSeq'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.s,
      children: [
        Text(
          missing ? l.wakeStage2GapNotice : l.wakeStage2NoSeqNotice,
          style: WText.caption,
        ),
        WideButton(
          missing
              ? (loading ? l.voiceDownloadLoading : l.wakeStage2GapLoad)
              : l.wakeStage2NoSeqEnroll,
          onPressed: missing
              ? (loading
                    ? null
                    : () => unawaited(
                        ref.read(modelStatesProvider.notifier).download(id),
                      ))
              : onEnroll,
        ),
      ],
    );
  }
}

/// Notice with „Sprachmodell laden“ while [wakeMissingModelsProvider] is
/// not empty; nothing otherwise. Replaces the cryptic error the start of
/// enrolling, calibrating or trying out would give without the models.
class WakeModelsNotice extends ConsumerWidget {
  /// Creates the notice. [optional] shows the hint for the re-check model
  /// ([wakeVerifyMissingProvider]) instead of the required models.
  const WakeModelsNotice({super.key, this.optional = false});

  /// Whether this is the optional Whisper hint.
  final bool optional;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = ref.watch(
      optional ? wakeVerifyMissingProvider : wakeMissingModelsProvider,
    );
    if (missing.isEmpty) return const SizedBox.shrink();
    final states = ref.watch(modelStatesProvider);
    final loading = missing.any(
      (m) =>
          states[m.id]?.phase == ModelPhase.downloading ||
          states[m.id]?.phase == ModelPhase.unpacking,
    );
    return Column(
      key: ValueKey(optional ? 'wakeVerifyMissing' : 'wakeModelsMissing'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.s,
      children: [
        Text(
          optional
              ? context.l10n.wakeModelsVerifyNeeds(
                  missing.map((m) => m.displayName).join(', '),
                )
              : context.l10n.wakeModelsNeedsModel(
                  missing.map((m) => m.displayName).join(', '),
                ),
          style: WText.caption,
        ),
        WideButton(
          loading
              ? context.l10n.voiceDownloadLoading
              : context.l10n.wakeModelsLoadModel,
          onPressed: loading
              ? null
              : () {
                  final notifier = ref.read(modelStatesProvider.notifier);
                  for (final m in missing) {
                    unawaited(notifier.download(m.id));
                  }
                },
        ),
      ],
    );
  }
}
