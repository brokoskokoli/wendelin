import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/voice_providers.dart';
import '../design/design.dart';
import 'model_download_row.dart';
import 'settings_page.dart';
import 'voice_screen.dart' show languageNames, sampleText;

/// Settings → Sprache → Stimmen (WP66): per language the offline voices
/// (female and male) to load, delete and choose, and a play button
/// („Probe hören“) on the chosen one. Only voices that are loaded take up space on the device.
class VoiceVoicesScreen extends ConsumerWidget {
  /// Creates the screen.
  const VoiceVoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(voiceSettingsProvider).value;
    if (settings == null) {
      return const SettingsPage(title: 'Stimmen', children: []);
    }
    final catalog = ref.watch(speechModelCatalogProvider);
    final states = ref.watch(modelStatesProvider);
    final notifier = ref.read(voiceSettingsProvider.notifier);
    String? effective(String lang) =>
        _effective(states, settings, catalog, lang);
    return SettingsPage(
      title: 'Stimmen',
      intro:
          'Wähle je Sprache die Offline-Stimme. Nur geladene Stimmen '
          'belegen Speicher; nicht gebrauchte kannst du löschen.',
      children: [
        for (final lang in languageNames.keys)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WSpace.m,
            children: [
              SettingsSection(
                title: languageNames[lang]!,
                children: [
                  for (final m in catalog.voicesFor(lang))
                    ModelDownloadRow(
                      model: m,
                      selected: effective(lang) == m.id,
                      extra: _ProbeButton(
                        key: Key('probe-$lang'),
                        onProbe: () => ref
                            .read(sherpaTtsProvider)
                            .speak(
                              sampleText(lang),
                              voice: m.id,
                              language: lang,
                              rate: settings.ttsRate,
                            ),
                      ),
                      onSelect: () => unawaited(
                        notifier.change(
                          (s) => s.copyWith(
                            sherpaVoices: {...s.sherpaVoices, lang: m.id},
                          ),
                        ),
                      ),
                      // Deleting the chosen voice drops the choice.
                      onDeleted: () {
                        if (settings.sherpaVoices[lang] != m.id) return;
                        unawaited(
                          notifier.change(
                            (s) => s.copyWith(
                              sherpaVoices: {...s.sherpaVoices}..remove(lang),
                            ),
                          ),
                        );
                      },
                    ),
                  if (_missingChoice(settings, catalog, lang, effective(lang))
                      case final speaking?)
                    Padding(
                      padding: const EdgeInsets.all(WSpace.l),
                      child: Text(
                        'Gewählte Stimme nicht geladen – es spricht '
                        '${catalog.byId(speaking)!.displayName}.',
                        key: Key('hint-$lang'),
                        style: WText.detail,
                      ),
                    ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  /// The voice that speaks for [language] (same rule as the speech output).
  static String? _effective(
    Map<String, ModelState> states,
    VoiceSettings settings,
    SpeechModelCatalog catalog,
    String language,
  ) => effectiveSherpaVoice(
    chosen: settings.sherpaVoiceFor(language, catalog),
    available: [
      for (final m in catalog.voicesFor(language))
        if (states[m.id]?.phase == ModelPhase.installed) m.id,
    ],
  );

  /// The speaking voice if a voice was chosen explicitly but is not loaded.
  static String? _missingChoice(
    VoiceSettings settings,
    SpeechModelCatalog catalog,
    String language,
    String? speaking,
  ) {
    final chosen = settings.sherpaVoices[language];
    return chosen != null && speaking != null && chosen != speaking
        ? speaking
        : null;
  }
}

/// Play button „Probe hören“ on the chosen voice. It shows a spinner right
/// after the tap (synthesis takes 1–2 s) until the sample has ended.
class _ProbeButton extends StatefulWidget {
  const _ProbeButton({super.key, required this.onProbe});

  final Future<void> Function() onProbe;

  @override
  State<_ProbeButton> createState() => _ProbeButtonState();
}

class _ProbeButtonState extends State<_ProbeButton> {
  bool _busy = false;

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await widget.onProbe();
    } on Object {
      // A failed sample only ends the spinner.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _busy
      ? const SizedBox.square(
          dimension: WSize.touchMin,
          child: Center(
            child: SizedBox.square(
              dimension: WSize.spinner,
              child: CircularProgressIndicator(
                strokeWidth: WSize.spinnerStroke,
                color: WColors.accent,
                semanticsLabel: 'Probe wird vorbereitet …',
              ),
            ),
          ),
        )
      : IconButton(
          onPressed: () => unawaited(_start()),
          tooltip: 'Probe hören',
          color: WColors.accent,
          icon: const Icon(Icons.play_arrow_rounded),
        );
}
