import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../voice/voice_metrics.dart';
import '../design/design.dart';
import '../onboarding/voice_download_step.dart';
import 'settings_page.dart';

/// Settings → Sprache → Messwerte (WP103): latency, real-time factor and
/// process memory of the last utterances, for the device test.
class VoiceMetricsScreen extends ConsumerWidget {
  /// Creates the screen.
  const VoiceMetricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final metrics = ref.watch(voiceMetricsProvider);
    return SettingsPage(
      title: l.voiceScreenMetrics,
      intro: l.voiceMetricsIntro,
      children: [
        if (metrics.isEmpty)
          Text(l.voiceMetricsEmpty, style: WText.caption)
        else ...[
          SettingsSection(
            title: l.voiceScreenMetrics,
            children: [
              for (final m in metrics)
                SettingsRow(
                  title:
                      '${m.kind == VoiceMetricKind.stt ? l.voiceMetricsStt : l.voiceMetricsTts}: ${m.model}',
                  detail: l.voiceMetricsRow(
                    '${m.compute.inMilliseconds}',
                    '${m.audio.inMilliseconds}',
                    m.rtf.toStringAsFixed(2),
                    m.rssBytes == null ? '?' : sizeLabel(l, m.rssBytes!),
                  ),
                ),
            ],
          ),
          TextButton(
            onPressed: () => ref.read(voiceMetricsProvider.notifier).clear(),
            child: Text(l.voiceMetricsClear),
          ),
        ],
      ],
    );
  }
}
