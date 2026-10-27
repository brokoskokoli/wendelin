import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/preferences.dart';
import '../../di/voice_providers.dart';
import '../../l10n/l10n.dart';
import '../../platform/device_memory.dart';
import '../design/design.dart';
import '../onboarding/voice_download_step.dart';
import '../routes.dart';
import '../voice/microphone_access.dart';
import 'model_download_row.dart';
import 'settings_page.dart';
import 'voice_conversation_section.dart';
import 'voice_spoken_section.dart';

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
      return SettingsPage(title: context.l10n.areaSpeech, children: []);
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
      title: context.l10n.areaSpeech,
      intro: context.l10n.voiceScreenIntro,
      children: [
        ..._recognition(
          context.l10n,
          ref,
          settings,
          catalog,
          change,
          sttReady: sttReady,
        ),
        ..._language(context.l10n, settings, appLanguage, change),
        _SpeechOutput(settings: settings, change: change),
        ..._tuning(context.l10n, settings, change),
        SettingsSection(
          title: context.l10n.voiceScreenKeepModel,
          children: [
            SettingsRow(
              title: context.l10n.voiceScreenKeepModel,
              detail: context.l10n.voiceScreenKeepModelHint,
              trailing: WSwitch(
                value: settings.keepModelLoaded,
                semanticLabel: context.l10n.voiceScreenKeepModelLabel,
                onChanged: (v) => change((s) => s.copyWith(keepModelLoaded: v)),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: context.l10n.onboardingWakeWord,
          children: [
            SettingsRow(
              title: context.l10n.voiceScreenLearnsVoice,
              detail: context.l10n.voiceScreenLearnsVoiceDetail,
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.wakeWord),
            ),
          ],
        ),
        SettingsSection(
          title: context.l10n.speakerRowTitle,
          children: [
            SettingsRow(
              title: context.l10n.speakerRowTitle,
              detail: context.l10n.speakerRowDetail,
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.speaker),
            ),
          ],
        ),
        const _Microphone(),
        SpokenVersionSection(settings: settings, change: change),
        ConversationSettingsSection(
          settings: settings,
          change: change,
          bargeInAvailable: ref.watch(bargeInAvailableProvider),
        ),
        SettingsSection(
          title: context.l10n.voiceScreenMetrics,
          children: [
            SettingsRow(
              title: context.l10n.voiceScreenMetrics,
              detail: context.l10n.voiceScreenMetricsDetail,
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.voiceMetrics),
            ),
          ],
        ),
        SettingsSection(
          title: context.l10n.voiceScreenModelLicenses,
          children: [
            SettingsRow(
              title: context.l10n.voiceScreenModelLicenses,
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.voiceLicenses),
            ),
          ],
        ),
      ],
    );
  }
}

typedef _Change = void Function(VoiceSettings Function(VoiceSettings));

/// Whisper models, voice activity model and the hints below them.
List<Widget> _recognition(
  AppLocalizations l,
  WidgetRef ref,
  VoiceSettings settings,
  SpeechModelCatalog catalog,
  _Change change, {
  required bool sttReady,
}) => [
  SettingsSection(
    title: l.voiceScreenRecognition,
    children: [
      for (final m in catalog.ofKind(SpeechModelKind.stt))
        ModelDownloadRow(
          model: m,
          recommended: m.id == SpeechModelCatalog.parakeetV3.id,
          selected: settings.sttModel == m.id,
          onSelect: () => change((s) => s.copyWith(sttModel: m.id)),
        ),
      ModelDownloadRow(model: SpeechModelCatalog.sileroVad),
    ],
  ),
  if (!sttReady) InfoBox(l.voiceScreenRecognitionHint),
  if (_recommendSmall(ref, settings))
    InfoBox(
      l.voiceScreenRecommendSmall(
        sizeLabel(l, SpeechModelCatalog.whisperSmall.sizeBytes),
      ),
    ),
];

/// Language of the spoken input.
List<Widget> _language(
  AppLocalizations l,
  VoiceSettings settings,
  String appLanguage,
  _Change change,
) => [
  SettingsSection(
    title: l.voiceScreenSpokenLanguage,
    children: [
      for (final (value, title) in [
        (
          VoiceSettings.followApp,
          l.voiceScreenLikeApp(languageNames[appLanguage] ?? appLanguage),
        ),
        (VoiceSettings.detect, l.voiceScreenDetectAuto),
        for (final e in languageNames.entries) (e.key, e.value),
      ])
        _ChoiceRow(
          title: title,
          selected: settings.sttLanguage == value,
          onTap: () => change((s) => s.copyWith(sttLanguage: value)),
        ),
    ],
  ),
  InfoBox(l.voiceScreenFixedLanguageHint),
];

/// Minimum speech duration and VAD sensitivity.
List<Widget> _tuning(
  AppLocalizations l,
  VoiceSettings settings,
  _Change change,
) => [
  SettingsSection(
    title: l.voiceScreenFineTuning,
    children: [
      _ChipsRow(
        title: l.voiceScreenMinSpeech,
        detail: l.voiceScreenMinSpeechDetail,
        values: VoiceSettings.minSpeechChoices,
        selected: settings.minSpeechMs,
        label: (v) => l.voiceScreenMs(v),
        onSelected: (v) => change((s) => s.copyWith(minSpeechMs: v)),
      ),
      _ChipsRow(
        title: l.voiceScreenSensitivity,
        detail: l.voiceScreenSensitivityDetail,
        values: VoiceSettings.thresholds,
        selected: settings.vadThreshold,
        label: (v) => v.toStringAsFixed(1).replaceAll('.', ','),
        onSelected: (v) => change((s) => s.copyWith(vadThreshold: v)),
      ),
    ],
  ),
];

/// Whether to suggest small (WP33): base is active, small is not on the
/// device and the device does not have little memory.
bool _recommendSmall(WidgetRef ref, VoiceSettings settings) {
  const small = SpeechModelCatalog.whisperSmall;
  return settings.sttModel == SpeechModelCatalog.whisperBase.id &&
      ref.watch(modelStatesProvider)[small.id]?.phase != ModelPhase.installed &&
      !isLowMemory(ref.watch(deviceMemoryProvider).value);
}

class _SpeechOutput extends ConsumerWidget {
  const _SpeechOutput({required this.settings, required this.change});

  final VoiceSettings settings;
  final void Function(VoiceSettings Function(VoiceSettings)) change;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(ttsSelectionProvider).value;
    final sampleLang = sampleLanguage(settings, ref.watch(languageProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WSpace.l18,
      children: [
        SettingsSection(
          title: context.l10n.voiceScreenSpeechOutput,
          children: [
            for (final (value, title, detail) in [
              (
                TtsPreference.automatic,
                context.l10n.voiceScreenAutomatic,
                context.l10n.voiceScreenAutomaticDetail,
              ),
              (TtsPreference.system, context.l10n.voiceScreenSystemVoice, null),
              (
                TtsPreference.sherpa,
                context.l10n.voiceScreenOfflineVoice,
                'sherpa-onnx',
              ),
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
          Text(ttsSelectionText(context.l10n, selection), style: WText.caption),
        SettingsSection(
          title: context.l10n.voiceScreenOfflineVoices,
          children: [
            SettingsRow(
              title: context.l10n.voiceScreenVoices,
              detail: context.l10n.voiceScreenVoicesDetail,
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.voices),
            ),
          ],
        ),
        SettingsSection(
          title: context.l10n.voiceScreenVoiceAndTempo,
          children: [
            SettingsRow(
              title: context.l10n.voiceScreenSystemVoiceTitle,
              detail:
                  settings.ttsVoice ?? context.l10n.voiceScreenLanguageDefault,
              onTap: selection?.engine != TtsEngine.system
                  ? null
                  : () => unawaited(_chooseVoice(context, selection!.tts!)),
            ),
            _ChipsRow(
              title: context.l10n.voiceScreenTempo,
              values: VoiceSettings.rates,
              selected: settings.ttsRate,
              label: (v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}×',
              onSelected: (v) => change((s) => s.copyWith(ttsRate: v)),
            ),
          ],
        ),
        WideButton(
          context.l10n.voiceScreenListen,
          onPressed: selection?.tts == null
              ? null
              : () => unawaited(
                  selection!.tts!.speak(
                    sampleText(sampleLang),
                    voice: settings.ttsVoice,
                    language: sampleLang,
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
        title: Text(context.l10n.voiceScreenVoice, style: WText.label),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(
              context.l10n.voiceScreenLanguageDefaultChip,
              style: WText.body,
            ),
          ),
          for (final v in voices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(v.id),
              child: Text(
                context.l10n.voiceScreenVoiceLanguage(
                  v.name ?? v.id,
                  v.language,
                ),
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

/// Language of the „Probe hören“ sample: the fixed spoken language, else
/// the app language (B13).
String sampleLanguage(VoiceSettings settings, String appLanguage) =>
    settings.effectiveLanguage(appLanguage) ?? appLanguage;

/// Sample sentence in [language] (de/fr/en, else German).
String sampleText(String language) =>
    switch (language.split(RegExp('[-_]')).first) {
      'fr' => 'Bonjour, je suis Wendelin.',
      'en' => 'Hello, I am Wendelin.',
      _ => 'Hallo, ich bin Wendelin.',
    };

/// Status line for the chosen speech output.
String ttsSelectionText(AppLocalizations l, TtsSelection s) =>
    switch (s.engine) {
      TtsEngine.system when s.fallback => l.voiceScreenNoOfflineVoice,
      TtsEngine.system => l.voiceScreenSpeaksSystem,
      TtsEngine.sherpa when s.fallback => l.voiceScreenNoSystemVoice,
      TtsEngine.sherpa => l.voiceScreenSpeaksOffline,
      TtsEngine.none => l.voiceScreenNoSpeech,
    };

class _Microphone extends ConsumerWidget {
  const _Microphone();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final granted = ref.watch(microphoneGrantedProvider).value;
    return SettingsSection(
      title: context.l10n.voiceScreenMicrophone,
      children: [
        SettingsRow(
          title: context.l10n.voiceScreenMicrophoneTitle,
          detail: switch (granted) {
            true => 'erlaubt',
            false => context.l10n.voiceScreenNotAllowed,
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
                  child: Text(context.l10n.allow),
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
        ? CheckStatusIcon(CheckStatus.ok, semanticLabel: context.l10n.selected)
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
