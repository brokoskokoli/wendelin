import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/preferences.dart';
import '../../di/voice_providers.dart';
import '../design/design.dart';
import '../voice/microphone_access.dart';
import 'model_download_row.dart';
import 'settings_page.dart';

/// Language names (BCP 47 primary subtag → name).
const languageNames = {'de': 'Deutsch', 'fr': 'Français', 'en': 'English'};

/// Whether the microphone permission is granted (without asking).
final microphoneGrantedProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(microphoneProvider).hasPermission(request: false),
);

/// Settings → Sprache: Whisper model and language, speech output (engine,
/// offline voices, voice, tempo), fine tuning of the endpointing,
/// microphone permission and the licenses of the speech models.
class VoiceScreen extends ConsumerWidget {
  /// Creates the screen.
  const VoiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(voiceSettingsProvider).value;
    if (settings == null) {
      return const SettingsPage(title: 'Sprache', children: []);
    }
    final catalog = ref.watch(speechModelCatalogProvider);
    final notifier = ref.read(voiceSettingsProvider.notifier);
    void change(VoiceSettings Function(VoiceSettings) f) =>
        unawaited(notifier.change(f));
    final appLanguage = ref.watch(languageProvider);
    final states = ref.watch(modelStatesProvider);
    final sttReady =
        states[settings.sttModel]?.phase == ModelPhase.installed &&
        states[SpeechModelCatalog.sileroVad.id]?.phase == ModelPhase.installed;

    return SettingsPage(
      title: 'Sprache',
      intro:
          'Wendelin erkennt Sprache auf dem Gerät (Whisper). Die Modelle '
          'werden einmal geladen und bleiben auf dem Gerät.',
      children: [
        SettingsSection(
          title: 'Spracherkennung',
          children: [
            for (final m in catalog.ofKind(SpeechModelKind.stt))
              ModelDownloadRow(
                model: m,
                selected: settings.sttModel == m.id,
                onSelect: () => change((s) => s.copyWith(sttModel: m.id)),
              ),
            ModelDownloadRow(model: SpeechModelCatalog.sileroVad),
          ],
        ),
        if (!sttReady)
          Text(
            'Für die Spracheingabe braucht Wendelin das gewählte '
            'Whisper-Modell und die Sprachaktivitätserkennung.',
            style: WText.caption,
          ),
        SettingsSection(
          title: 'Gesprochene Sprache',
          children: [
            for (final (value, title) in [
              (
                VoiceSettings.followApp,
                'Wie die App (${languageNames[appLanguage] ?? appLanguage})',
              ),
              (VoiceSettings.detect, 'Automatisch erkennen'),
              for (final e in languageNames.entries) (e.key, e.value),
            ])
              _ChoiceRow(
                title: title,
                selected: settings.sttLanguage == value,
                onTap: () => change((s) => s.copyWith(sttLanguage: value)),
              ),
          ],
        ),
        Text(
          'Mit fester Sprache erkennt Whisper kurze Sätze zuverlässiger.',
          style: WText.caption,
        ),
        _SpeechOutput(settings: settings, change: change),
        SettingsSection(
          title: 'Feinabstimmung',
          children: [
            _ChipsRow(
              title: 'Mindestsprechdauer',
              detail: 'Kürzere Geräusche (Klicks, Atmer) werden ignoriert.',
              values: VoiceSettings.minSpeechChoices,
              selected: settings.minSpeechMs,
              label: (v) => '$v ms',
              onSelected: (v) => change((s) => s.copyWith(minSpeechMs: v)),
            ),
            _ChipsRow(
              title: 'Empfindlichkeit der Spracherkennung',
              detail:
                  'Schwelle von Silero VAD: niedriger hört leiser, höher '
                  'ignoriert mehr Geräusche.',
              values: VoiceSettings.thresholds,
              selected: settings.vadThreshold,
              label: (v) => v.toStringAsFixed(1).replaceAll('.', ','),
              onSelected: (v) => change((s) => s.copyWith(vadThreshold: v)),
            ),
          ],
        ),
        const _Microphone(),
        SettingsSection(
          title: 'Lizenzen der Sprachmodelle',
          children: [
            for (final m in catalog.models)
              SettingsRow(
                title: m.displayName,
                detail: [m.license, ?m.attribution].join('\n'),
              ),
          ],
        ),
      ],
    );
  }
}

class _SpeechOutput extends ConsumerWidget {
  const _SpeechOutput({required this.settings, required this.change});

  final VoiceSettings settings;
  final void Function(VoiceSettings Function(VoiceSettings)) change;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(speechModelCatalogProvider);
    final selection = ref.watch(ttsSelectionProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.l18,
      children: [
        SettingsSection(
          title: 'Sprachausgabe',
          children: [
            for (final (value, title, detail) in [
              (
                TtsPreference.automatic,
                'Automatisch',
                'Systemstimme, sonst Offline-Stimme',
              ),
              (TtsPreference.system, 'Systemstimme', null),
              (TtsPreference.sherpa, 'Offline-Stimme', 'sherpa-onnx'),
            ])
              _ChoiceRow(
                title: title,
                detail: detail,
                selected: settings.tts == value,
                onTap: () => change((s) => s.copyWith(tts: value)),
              ),
          ],
        ),
        if (selection != null)
          Text(ttsSelectionText(selection), style: WText.caption),
        SettingsSection(
          title: 'Offline-Stimmen',
          children: [
            for (final m in catalog.ofKind(SpeechModelKind.tts))
              ModelDownloadRow(model: m),
          ],
        ),
        SettingsSection(
          title: 'Stimme und Tempo',
          children: [
            SettingsRow(
              title: 'Stimme',
              detail: settings.ttsVoice ?? 'Standard der Sprache',
              onTap: selection?.tts == null
                  ? null
                  : () => unawaited(_chooseVoice(context, selection!.tts!)),
            ),
            _ChipsRow(
              title: 'Tempo',
              values: VoiceSettings.rates,
              selected: settings.ttsRate,
              label: (v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}×',
              onSelected: (v) => change((s) => s.copyWith(ttsRate: v)),
            ),
          ],
        ),
        WideButton(
          'Probe hören',
          onPressed: selection?.tts == null
              ? null
              : () => unawaited(
                  selection!.tts!.speak(
                    'Hallo, ich bin Wendelin.',
                    voice: settings.ttsVoice,
                    language: ref.read(languageProvider),
                    rate: settings.ttsRate,
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _chooseVoice(BuildContext context, TextToSpeech tts) async {
    final lang = languageNames.keys.toSet();
    final voices = [
      for (final v in await tts.voices())
        if (lang.contains(v.language.split(RegExp('[-_]')).first)) v,
    ];
    if (!context.mounted) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: WColors.surface,
        title: Text('Stimme', style: WText.label),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text('Standard der Sprache', style: WText.body),
          ),
          for (final v in voices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(v.id),
              child: Text(
                '${v.name ?? v.id} (${v.language})',
                style: WText.body,
              ),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    change(
      (s) => chosen.isEmpty
          ? s.copyWith(clearVoice: true)
          : s.copyWith(ttsVoice: chosen),
    );
  }
}

/// German status line for the chosen speech output.
String ttsSelectionText(TtsSelection s) => switch (s.engine) {
  TtsEngine.system when s.fallback =>
    'Keine Offline-Stimme für diese Sprache geladen – Wendelin spricht mit '
        'der Systemstimme.',
  TtsEngine.system => 'Wendelin spricht mit der Systemstimme.',
  TtsEngine.sherpa when s.fallback =>
    'Keine Systemstimme installiert – Wendelin spricht mit der '
        'Offline-Stimme.',
  TtsEngine.sherpa => 'Wendelin spricht mit der Offline-Stimme.',
  TtsEngine.none =>
    'Keine Sprachausgabe verfügbar: Antworten erscheinen nur auf dem '
        'Bildschirm. Lade eine Offline-Stimme.',
};

class _Microphone extends ConsumerWidget {
  const _Microphone();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final granted = ref.watch(microphoneGrantedProvider).value;
    return SettingsSection(
      title: 'Mikrofon',
      children: [
        SettingsRow(
          title: 'Mikrofon',
          detail: switch (granted) {
            true => 'erlaubt',
            false => 'nicht erlaubt',
            null => '…',
          },
          trailing: granted == false
              ? OutlinedButton(
                  onPressed: () async {
                    await ensureMicrophoneAccess(
                      context,
                      ref.read(microphoneProvider),
                    );
                    ref.invalidate(microphoneGrantedProvider);
                  },
                  child: const Text('Erlauben'),
                )
              : null,
        ),
      ],
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  final String title;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SettingsRow(
    title: title,
    detail: detail,
    onTap: onTap,
    trailing: selected
        ? const CheckStatusIcon(CheckStatus.ok, semanticLabel: 'gewählt')
        : null,
  );
}

class _ChipsRow<T> extends StatelessWidget {
  const _ChipsRow({
    required this.title,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.detail,
  });

  final String title;
  final String? detail;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final void Function(T) onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: WSpace.l,
      vertical: WSpace.m,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: WSpace.s,
      children: [
        Text(title, style: WText.label),
        if (detail != null) Text(detail!, style: WText.detail),
        Wrap(
          spacing: WSpace.s,
          runSpacing: WSpace.s,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(label(v)),
                selected: v == selected,
                onSelected: (_) => onSelected(v),
              ),
          ],
        ),
      ],
    ),
  );
}
