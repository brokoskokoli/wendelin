import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/app_settings.dart';
import '../../di/core_providers.dart';
import '../../di/wake_providers.dart';
import '../../platform/voice/record_audio_input.dart';
import '../design/design.dart';

/// Margin choices of the developer setting (text as stored).
const bargeMarginChoices = ['0.05', '0.00', '-0.05'];

/// Whether a developer variant (source or margin) other than the default is
/// active; the conversation settings show a hint then. The sheet invalidates
/// it with every change.
final bargeVariantActiveProvider = FutureProvider<bool>((ref) async {
  final s = ref.read(storageProvider).settings;
  final source = SpeechCapture.parse(await s.get(AppSettings.bargeSource));
  final margin = await s.get(AppSettings.bargeMargin);
  return source != SpeechCapture.communication ||
      (margin != null &&
          bargeMarginChoices.contains(margin) &&
          margin != bargeMarginChoices.first);
});

/// Opens the hidden developer sheet „Barge-in-Variante“ (WP72): long press
/// on „Unterbrechen während der Antwort“. Both choices apply to the next
/// spoken answer; `docs/testing/m4-device.md` 11.6 explains how to read the
/// `barge-diag` lines for each variant.
Future<void> showBargeDebugSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const BargeDebugSheet(),
    );

/// Content of [showBargeDebugSheet].
class BargeDebugSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const BargeDebugSheet({super.key});

  @override
  ConsumerState<BargeDebugSheet> createState() => _State();
}

class _State extends ConsumerState<BargeDebugSheet> {
  SpeechCapture _source = SpeechCapture.communication;
  String _margin = bargeMarginChoices.first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = ref.read(storageProvider).settings;
    final source = await s.get(AppSettings.bargeSource);
    final margin = await s.get(AppSettings.bargeMargin);
    if (!mounted) return;
    setState(() {
      _source = SpeechCapture.parse(source);
      if (bargeMarginChoices.contains(margin)) _margin = margin!;
    });
  }

  Future<void> _set(SpeechCapture? source, String? margin) async {
    final s = ref.read(storageProvider).settings;
    if (source != null) await s.set(AppSettings.bargeSource, source.name);
    if (margin != null) await s.set(AppSettings.bargeMargin, margin);
    // The detector reads the margin when it is built.
    ref.invalidate(wakeBargeInDetectorProvider);
    ref.invalidate(bargeVariantActiveProvider);
    if (!mounted) return;
    setState(() {
      if (source != null) _source = source;
      if (margin != null) _margin = margin;
    });
  }

  Future<void> _reset() =>
      _set(SpeechCapture.communication, bargeMarginChoices.first);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(WSpace.l),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: WSpace.s,
      children: [
        Text('Barge-in-Variante (Entwickler)', style: WText.label),
        Text('Quelle des Mikrofons während der Antwort:', style: WText.detail),
        Wrap(
          spacing: WSpace.s,
          children: [
            for (final v in SpeechCapture.values)
              ChoiceChip(
                label: Text(switch (v) {
                  SpeechCapture.communication =>
                    'Kommunikation + AEC (Standard)',
                  SpeechCapture.recognitionAec => 'Erkennung + AEC',
                  SpeechCapture.recognition => 'Erkennung, ohne AEC',
                }),
                selected: _source == v,
                onSelected: (_) => _set(v, null),
              ),
          ],
        ),
        Text('Zusätzliche Schwelle (Standard +0,05):', style: WText.detail),
        Wrap(
          spacing: WSpace.s,
          children: [
            for (final m in bargeMarginChoices)
              ChoiceChip(
                label: Text(
                  m == bargeMarginChoices.first ? '$m (Standard)' : m,
                ),
                selected: _margin == m,
                onSelected: (_) => _set(null, m),
              ),
          ],
        ),
        TextButton(
          onPressed:
              _source == SpeechCapture.communication &&
                  _margin == bargeMarginChoices.first
              ? null
              : _reset,
          child: const Text('Zurücksetzen'),
        ),
      ],
    ),
  );
}
