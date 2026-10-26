import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/app_settings.dart';
import '../../di/core_providers.dart';
import '../../di/developer_mode.dart';
import '../../di/voice_providers.dart';
import '../../di/wake_providers.dart';
import '../../l10n/l10n.dart';
import '../../platform/voice/record_audio_input.dart';
import '../design/design.dart';

/// Margin choices of the developer setting (text as stored).
const bargeMarginChoices = ['0.05', '0.00', '-0.05'];

/// What each microphone source means (WP80), shown below the choices.
Map<SpeechCapture, String> bargeSourceHelp(AppLocalizations l) => {
  SpeechCapture.communication: l.bargeDebugHelpCommunication,
  SpeechCapture.recognitionAec: l.bargeDebugHelpRecognitionAec,
  SpeechCapture.recognition: l.bargeDebugHelpRecognition,
};

/// What the additional threshold does (WP80).
String bargeMarginHelp(AppLocalizations l) => l.bargeDebugHelpMargin;

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

/// Opens the sheet „Erweitert“ (WP80, was hidden behind a long press in
/// WP72): button next to „Unterbrechen während der Antwort“. Both choices
/// apply to the next spoken answer; `docs/testing/m4-device.md` 11.6
/// explains how to read the `barge-diag` lines for each variant.
Future<void> showBargeDebugSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
  bool _communication = false;
  String _bonus = hotwordsBonusChoices.first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = ref.read(storageProvider).settings;
    final source = await s.get(AppSettings.bargeSource);
    final margin = await s.get(AppSettings.bargeMargin);
    final comm = await s.get(AppSettings.speechCommunication);
    final bonus = await s.get(AppSettings.hotwordsBonus);
    if (!mounted) return;
    setState(() {
      if (hotwordsBonusChoices.contains(bonus)) _bonus = bonus!;
      _communication = comm ?? false;
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

  Future<void> _setBonus(String value) async {
    await ref
        .read(storageProvider)
        .settings
        .set(AppSettings.hotwordsBonus, value);
    // The recognizer is built again with the new bonus.
    ref.invalidate(hotwordsBonusProvider);
    if (!mounted) return;
    setState(() => _bonus = value);
  }

  /// WP146: developer setting, bonus of the hint terms.
  List<Widget> _bonusSection(BuildContext context) => [
    Text(context.l10n.hotwordsBonusTitle, style: WText.label),
    Wrap(
      spacing: WSpace.s,
      children: [
        for (final b in hotwordsBonusChoices)
          ChoiceChip(
            label: Text(
              b == hotwordsBonusChoices.first
                  ? context.l10n.bargeDebugDefaultSuffix(b.replaceAll('.', ','))
                  : b.replaceAll('.', ','),
            ),
            selected: _bonus == b,
            onSelected: (_) => _setBonus(b),
          ),
      ],
    ),
    Text(context.l10n.hotwordsBonusHelp, style: WText.detail),
  ];

  Future<void> _setCommunication(bool value) async {
    await ref
        .read(storageProvider)
        .settings
        .set(AppSettings.speechCommunication, value);
    if (!mounted) return;
    setState(() => _communication = value);
  }

  Future<void> _reset() =>
      _set(SpeechCapture.communication, bargeMarginChoices.first);

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(WSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: WSpace.s,
        children: [
          Text(context.l10n.bargeDebugTitle, style: WText.label),
          Text(context.l10n.bargeDebugIntro, style: WText.detail),
          Text(context.l10n.bargeDebugMicDuring, style: WText.label),
          Wrap(
            spacing: WSpace.s,
            children: [
              for (final v in SpeechCapture.values)
                ChoiceChip(
                  label: Text(switch (v) {
                    SpeechCapture.communication =>
                      context.l10n.bargeDebugMicCommunication,
                    SpeechCapture.recognitionAec =>
                      context.l10n.bargeDebugMicRecognitionAec,
                    SpeechCapture.recognition =>
                      context.l10n.bargeDebugMicRecognition,
                  }),
                  selected: _source == v,
                  onSelected: (_) => _set(v, null),
                ),
            ],
          ),
          for (final v in SpeechCapture.values)
            Text(bargeSourceHelp(context.l10n)[v]!, style: WText.detail),
          Text(context.l10n.bargeDebugExtraThreshold, style: WText.label),
          Wrap(
            spacing: WSpace.s,
            children: [
              for (final m in bargeMarginChoices)
                ChoiceChip(
                  label: Text(
                    m == bargeMarginChoices.first
                        ? context.l10n.bargeDebugDefaultSuffix(
                            m.replaceAll('.', ','),
                          )
                        : m.replaceAll('.', ','),
                  ),
                  selected: _margin == m,
                  onSelected: (_) => _set(null, m),
                ),
            ],
          ),
          Text(bargeMarginHelp(context.l10n), style: WText.detail),
          TextButton(
            onPressed:
                _source == SpeechCapture.communication &&
                    _margin == bargeMarginChoices.first
                ? null
                : _reset,
            child: Text(context.l10n.reset),
          ),
          // WP148: only in developer mode; a stored value stays in effect.
          if (ref.watch(developerModeProvider)) ..._bonusSection(context),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.speechCommunicationTitle),
            subtitle: Text(context.l10n.speechCommunicationHelp),
            value: _communication,
            onChanged: _setCommunication,
          ),
        ],
      ),
    ),
  );
}
