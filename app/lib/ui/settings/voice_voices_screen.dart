import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/voice_providers.dart';
import '../../l10n/l10n.dart';
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
      return SettingsPage(title: context.l10n.voiceScreenVoices, children: []);
    }
    final catalog = ref.watch(speechModelCatalogProvider);
    final states = ref.watch(modelStatesProvider);
    final notifier = ref.read(voiceSettingsProvider.notifier);
    String? effective(String lang) =>
        _effective(states, settings, catalog, lang);
    return SettingsPage(
      title: context.l10n.voiceScreenVoices,
      intro: context.l10n.voiceVoicesIntro,
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
                        tts: ref.read(sherpaTtsProvider),
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
                        context.l10n.voiceVoicesNotLoaded(
                          catalog.byId(speaking)!.displayName,
                        ),
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

/// Play button „Probe hören“ on the chosen voice. Right after the tap a
/// spinner („wird vorbereitet“) shows while the sample is synthesised
/// (1–2 s); once it plays the button is a stop button. A failed sample
/// shows a short note.
class _ProbeButton extends StatefulWidget {
  const _ProbeButton({super.key, required this.tts, required this.onProbe});

  final TextToSpeech tts;
  final Future<void> Function() onProbe;

  @override
  State<_ProbeButton> createState() => _ProbeButtonState();
}

enum _ProbePhase { idle, preparing, playing }

class _ProbeButtonState extends State<_ProbeButton> {
  _ProbePhase _phase = _ProbePhase.idle;
  StreamSubscription<TtsState>? _states;

  @override
  void dispose() {
    unawaited(_states?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _phase = _ProbePhase.preparing);
    await _states?.cancel();
    _states = widget.tts.states.listen((s) {
      if (s == TtsState.speaking && mounted) {
        setState(() => _phase = _ProbePhase.playing);
      }
    });
    try {
      await widget.onProbe();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(context.l10n.voiceVoicesSampleFailed)),
          );
      }
    } finally {
      await _states?.cancel();
      _states = null;
      if (mounted) setState(() => _phase = _ProbePhase.idle);
    }
  }

  @override
  Widget build(BuildContext context) => switch (_phase) {
    _ProbePhase.preparing => SizedBox.square(
      dimension: WSize.touchMin,
      child: Center(
        child: SizedBox.square(
          dimension: WSize.spinner,
          child: CircularProgressIndicator(
            strokeWidth: WSize.spinnerStroke,
            color: WColors.accent,
            semanticsLabel: context.l10n.voiceVoicesPreparing,
          ),
        ),
      ),
    ),
    _ProbePhase.playing => WIconButton(
      icon: WIcons.stop,
      tooltip: context.l10n.voiceVoicesStopSample,
      onPressed: () => unawaited(widget.tts.stop()),
    ),
    _ProbePhase.idle => WIconButton(
      icon: WIcons.play,
      tooltip: context.l10n.voiceScreenListen,
      onPressed: () => unawaited(_start()),
    ),
  };
}
