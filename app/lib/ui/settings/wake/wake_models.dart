import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../../di/voice_providers.dart';
import '../../../di/wake_providers.dart';
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
              ? 'Für die Nachprüfung Sprachmodell laden '
                    '(${missing.map((m) => m.displayName).join(', ')}).'
              : 'Dafür muss zuerst das Sprachmodell geladen werden '
                    '(${missing.map((m) => m.displayName).join(', ')}).',
          style: WText.caption,
        ),
        WideButton(
          loading ? 'Lädt …' : 'Sprachmodell laden',
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
