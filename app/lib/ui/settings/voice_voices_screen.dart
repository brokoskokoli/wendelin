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
                      selected: settings.sherpaVoiceFor(lang, catalog) == m.id,
                      onSelect: () => unawaited(
                        notifier.change(
                          (s) => s.copyWith(
                            sherpaVoices: {...s.sherpaVoices, lang: m.id},
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              WideButton(
                'Probe hören',
                key: Key('probe-$lang'),
                onPressed: _installed(states, settings, catalog, lang)
                    ? () => unawaited(
                        ref
                            .read(sherpaTtsProvider)
                            .speak(
                              sampleText(lang),
                              voice: settings.sherpaVoiceFor(lang, catalog),
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

  static bool _installed(
    Map<String, ModelState> states,
    VoiceSettings settings,
    SpeechModelCatalog catalog,
    String lang,
  ) {
    final id = settings.sherpaVoiceFor(lang, catalog);
    return id != null && states[id]?.phase == ModelPhase.installed;
  }
}
