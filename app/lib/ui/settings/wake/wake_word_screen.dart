import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../../di/wake_providers.dart';
import '../../../voice/wake/wake_storage.dart';
import '../../design/design.dart';
import '../model_download_row.dart';
import '../settings_page.dart';
import 'wake_calibrate_screen.dart';
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
      title: 'Aktivierungswort',
      intro:
          'Wendelin lernt deine Stimme: Du sagst „Wendelin“ etwa 15 Mal, '
          'danach erkennt er es auch im Alltag. Gespeichert werden nur '
          'Zahlenwerte, verschlüsselt auf dem Gerät. Audio wird nie '
          'gespeichert.',
      children: [
        WakeServiceSection(
          onEnroll: installed
              ? () => unawaited(_enroll(context, ref, speakers, null))
              : () => showHint(
                  context,
                  'Dafür muss zuerst das Sprachmodell geladen werden.',
                ),
        ),
        SettingsSection(
          title: 'Merkmalsmodelle',
          children: [
            ModelDownloadRow(
              model: SpeechModelCatalog.wakeFeatures,
              deletable: false,
            ),
          ],
        ),
        SettingsSection(
          title: 'Gelernte Stimmen',
          children: [
            if (speakers.isEmpty)
              const SettingsRow(
                title: 'Noch keine Stimme',
                detail: 'Lerne mit „Stimme einlernen“ deine Stimme ein.',
              ),
            for (final (i, s) in speakers.indexed)
              _SpeakerRow(speaker: s, number: i + 1),
          ],
        ),
        WideButton(
          speakers.isEmpty ? 'Stimme einlernen' : 'Weitere Person einlernen',
          onPressed: installed
              ? () => unawaited(_enroll(context, ref, speakers, null))
              : null,
        ),
        if (!installed) const WakeModelsNotice(),
        WideButton(
          'Kalibrieren (30 min, empfohlen)',
          onPressed: installed && speakers.isNotEmpty
              ? () => unawaited(_calibrate(context, ref, speakers))
              : null,
        ),
        WideButton(
          'Jetzt ausprobieren',
          onPressed: installed && speakers.isNotEmpty
              ? () => unawaited(_test(context, ref, speakers))
              : null,
        ),
        if (installed) const WakeModelsNotice(optional: true),
        if (speakers.isNotEmpty)
          WideButton(
            'Alle Stimmen löschen',
            onPressed: () => unawaited(_deleteAll(context, ref)),
          ),
      ],
    );
  }
}

String speakerLabel(WakeSpeaker s, int number) =>
    s.name.isEmpty ? 'Person $number' : s.name;

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
      widget.first ? 'Wer spricht?' : 'Wer kommt dazu?',
      style: WText.label,
    ),
    content: TextField(
      controller: _controller,
      decoration: const InputDecoration(hintText: 'Name (optional)'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('Weiter'),
      ),
    ],
  );
}

Future<void> _calibrate(
  BuildContext context,
  WidgetRef ref,
  List<WakeSpeaker> speakers,
) async {
  final speaker = await _pick(context, speakers, 'Wen kalibrieren?');
  if (speaker == null || !context.mounted) return;
  final templates = await ref.read(wakeStoreProvider).load(speaker.id);
  if (templates == null || !context.mounted) return;
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
    for (final s in speakers) ?await store.load(s.id),
  ];
  if (all.isEmpty || !context.mounted) return;
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
            child: Text(speakerLabel(s, i + 1)),
          ),
      ],
    ),
  );
}

Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
  final ok = await confirm(
    context,
    title: 'Alle Stimmen löschen?',
    message:
        'Wendelin vergisst alle eingelernten Stimmen. Du kannst sie später '
        'neu einlernen.',
    yes: 'Löschen',
  );
  if (!ok) return;
  await ref.read(wakeSpeakersProvider.notifier).removeAll();
}

class _SpeakerRow extends ConsumerWidget {
  const _SpeakerRow({required this.speaker, required this.number});

  final WakeSpeaker speaker;
  final int number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(wakeTemplatesProvider(speaker.id)).value;
    final all = ref.read(wakeSpeakersProvider).value ?? const [];
    return SettingsRow(
      title: speakerLabel(speaker, number),
      detail: templates == null
          ? 'Vorlagen fehlen. Bitte neu einlernen.'
          : '${templates.embeddings.length} Aufnahmen · Schwelle '
                '${templates.threshold.toStringAsFixed(2)}',
      trailing: PopupMenuButton<String>(
        tooltip: 'Aktionen für ${speakerLabel(speaker, number)}',
        onSelected: (v) async {
          if (v == 'again') {
            await _enroll(context, ref, all, speaker);
          } else {
            await ref.read(wakeSpeakersProvider.notifier).remove(speaker.id);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'again', child: Text('Neu einlernen')),
          PopupMenuItem(value: 'delete', child: Text('Löschen')),
        ],
      ),
    );
  }
}
