import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../../di/wake_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/wake/wake_stage2_gap.dart';
import '../../../voice/wake/wake_enroller.dart';
import '../../../voice/wake/wake_storage.dart';
import '../../design/design.dart';
import '../model_download_row.dart';
import '../settings_page.dart';
import 'wake_calibrate_screen.dart';
import 'wake_detector_section.dart';
import 'wake_enroll_screen.dart';
import 'wake_models.dart';
import 'wake_service_section.dart';
import 'wake_test_screen.dart';

/// Einstellungen → Sprache → Aktivierungswort (WP60): „Wendelin lernt deine
/// Stimme“. Einlernen (etwa 3 min), Kalibrieren (etwa 30 min, empfohlen),
/// weitere Personen, Ausprobieren, der Dienst-Schalter und die Nachprüfung
/// (WP50 b: [WakeServiceSection]).
class WakeWordScreen extends ConsumerWidget {
  /// Creates the screen.
  const WakeWordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speakers = ref.watch(wakeSpeakersProvider).value ?? const [];
    final installed = ref.watch(wakeMissingModelsProvider).isEmpty;
    return SettingsPage(
      title: context.l10n.onboardingWakeWord,
      intro: context.l10n.wakeWordIntro,
      children: [
        WakeServiceSection(
          onEnroll: installed
              ? () => unawaited(_enroll(context, ref, speakers, null))
              : () => showHint(context, context.l10n.wakeWordNeedsModel),
        ),
        const WakeDetectorSection(),
        SettingsSection(
          title: context.l10n.wakeWordFeatureModels,
          children: [
            ModelDownloadRow(
              model: SpeechModelCatalog.wakeFeatures,
              deletable: false,
            ),
          ],
        ),
        SettingsSection(
          title: context.l10n.wakeWordLearned,
          children: [
            if (speakers.isEmpty)
              SettingsRow(
                title: context.l10n.wakeWordNoVoice,
                detail: context.l10n.wakeWordNoVoiceHint,
              ),
            for (final (i, s) in speakers.indexed)
              _SpeakerRow(speaker: s, number: i + 1),
          ],
        ),
        WideButton(
          speakers.isEmpty
              ? context.l10n.wakeWordEnroll
              : context.l10n.wakeWordEnrollMore,
          onPressed: installed
              ? () => unawaited(_enroll(context, ref, speakers, null))
              : null,
        ),
        if (!installed) const WakeModelsNotice(),
        WideButton(
          context.l10n.wakeWordCalibrate,
          onPressed: installed && speakers.isNotEmpty
              ? () => unawaited(_calibrate(context, ref, speakers))
              : null,
        ),
        WideButton(
          context.l10n.wakeWordTryNow,
          onPressed: installed && speakers.isNotEmpty
              ? () => unawaited(_test(context, ref, speakers))
              : null,
        ),
        WakeStage2GapNotice(
          onEnroll: speakers.isEmpty
              ? null
              : () =>
                    unawaited(_enroll(context, ref, speakers, speakers.first)),
        ),
        if (installed &&
            ref.watch(wakeStage2GapProvider) != WakeStage2Gap.modelMissing)
          const WakeModelsNotice(optional: true),
        if (speakers.isNotEmpty)
          WideButton(
            context.l10n.wakeWordDeleteAll,
            onPressed: () => unawaited(_deleteAll(context, ref)),
          ),
      ],
    );
  }
}

String speakerLabel(AppLocalizations l, WakeSpeaker s, int number) =>
    s.name.isEmpty ? l.wakeWordPerson(number) : s.name;

Future<void> _enroll(
  BuildContext context,
  WidgetRef ref,
  List<WakeSpeaker> speakers,
  WakeSpeaker? again,
) async {
  var name = again?.name ?? '';
  if (again == null) {
    final entered = await _askName(context, speakers.isEmpty);
    if (entered == null || !context.mounted) return;
    name = entered;
  }
  final id = again?.id ?? 'sp${DateTime.now().microsecondsSinceEpoch}';
  await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => WakeEnrollScreen(speakerId: id, name: name),
    ),
  );
}

Future<String?> _askName(BuildContext context, bool first) =>
    showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(first: first),
    );

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.first});

  final bool first;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: WColors.surface,
    title: Text(
      widget.first
          ? context.l10n.wakeWordWhoSpeaks
          : context.l10n.wakeWordWhoJoins,
      style: WText.label,
    ),
    content: TextField(
      controller: _controller,
      decoration: InputDecoration(hintText: context.l10n.wakeWordNameOptional),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: Text(context.l10n.next),
      ),
    ],
  );
}

/// Old (raw) templates are ignored since WP134: say so instead of doing
/// nothing.
void _showOutdated(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(context.l10n.wakeWordTemplatesOutdated)),
    );
}

Future<void> _calibrate(
  BuildContext context,
  WidgetRef ref,
  List<WakeSpeaker> speakers,
) async {
  final speaker = await _pick(
    context,
    speakers,
    context.l10n.wakeWordWhoCalibrate,
  );
  if (speaker == null || !context.mounted) return;
  final templates = await ref.read(wakeStoreProvider).load(speaker.id);
  // Outdated (raw) templates cannot be used: record again first.
  if (!context.mounted) return;
  if (templates == null || templates.center != wakeCenterId) {
    _showOutdated(context);
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => WakeCalibrateScreen(templates: templates),
    ),
  );
}

Future<void> _test(
  BuildContext context,
  WidgetRef ref,
  List<WakeSpeaker> speakers,
) async {
  final store = ref.read(wakeStoreProvider);
  final all = <WakeTemplates>[
    for (final s in speakers)
      if (await store.load(s.id) case final t? when t.center == wakeCenterId) t,
  ];
  if (!context.mounted) return;
  if (all.isEmpty) {
    _showOutdated(context);
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => WakeTestScreen(speakers: all)),
  );
}

Future<WakeSpeaker?> _pick(
  BuildContext context,
  List<WakeSpeaker> speakers,
  String title,
) async {
  if (speakers.length == 1) return speakers.single;
  return showDialog<WakeSpeaker>(
    context: context,
    builder: (context) => SimpleDialog(
      backgroundColor: WColors.surface,
      title: Text(title, style: WText.label),
      children: [
        for (final (i, s) in speakers.indexed)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(s),
            child: Text(speakerLabel(context.l10n, s, i + 1)),
          ),
      ],
    ),
  );
}

Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
  final ok = await confirm(
    context,
    title: context.l10n.wakeWordDeleteAllTitle,
    message: context.l10n.wakeWordDeleteAllBody,
    yes: context.l10n.delete,
  );
  if (!ok) return;
  await ref.read(wakeSpeakersProvider.notifier).removeAll();
}

/// WP143: templates without sequences leave verifier B inactive; say so
/// (only once B is in use, i.e. its `mu` is no placeholder any more).
String _withVerifierHint(
  BuildContext context,
  String detail,
  WakeTemplates templates,
) => wakeVerifierBMuIsPlaceholder || templates.hasSequences
    ? detail
    : '$detail\n${context.l10n.wakeWordRelearnForVerifier}';

class _SpeakerRow extends ConsumerWidget {
  const _SpeakerRow({required this.speaker, required this.number});

  final WakeSpeaker speaker;
  final int number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(wakeTemplatesProvider(speaker.id)).value;
    final all = ref.read(wakeSpeakersProvider).value ?? [];
    return SettingsRow(
      title: speakerLabel(context.l10n, speaker, number),
      detail: templates == null
          ? context.l10n.wakeWordTemplatesMissing
          : templates.center != wakeCenterId
          ? context.l10n.wakeWordTemplatesOutdated
          : templates.embeddings.length < wakeEnrollMinimum
          ? context.l10n.wakeWordTemplatesFew(templates.embeddings.length)
          : _withVerifierHint(
              context,
              context.l10n.wakeWordRecordingsThreshold(
                templates.embeddings.length,
                templates.threshold.toStringAsFixed(2),
              ),
              templates,
            ),
      trailing: PopupMenuButton<String>(
        tooltip: context.l10n.wakeWordActionsFor(
          speakerLabel(context.l10n, speaker, number),
        ),
        onSelected: (v) async {
          if (v == 'again') {
            await _enroll(context, ref, all, speaker);
          } else {
            await ref.read(wakeSpeakersProvider.notifier).remove(speaker.id);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'again',
            child: Text(context.l10n.wakeWordRetrain),
          ),
          PopupMenuItem(value: 'delete', child: Text(context.l10n.delete)),
        ],
      ),
    );
  }
}
