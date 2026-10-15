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
/// (female and male) to load, delete and choose, and „Probe hören“ for the
/// chosen one. Only voices that are loaded take up space on the device.
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
              WideButton(
                'Probe hören',
                key: Key('probe-$lang'),
                onPressed: effective(lang) != null
                    ? () => unawaited(
                        ref
                            .read(sherpaTtsProvider)
                            .speak(
                              sampleText(lang),
                              voice: effective(lang),
                              language: lang,
                              rate: settings.ttsRate,
                            ),
                      )
                    : null,
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
