import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../pipeline/endpointer.dart';
import '../pipeline/voice_pipeline_config.dart';
import '../tts/tts_selector.dart';
import 'speech_model.dart';
import 'speech_model_catalog.dart';

/// Settings of Einstellungen → Sprache.
@immutable
final class VoiceSettings {
  /// Creates the settings; defaults calibrated in
  /// `docs/notes/stt-wer-2026-10-13.md` (whisper-small with a fixed
  /// language since WP33; see the app's `VoiceSettingsNotifier` for base).
  const VoiceSettings({
    this.sttModel = 'whisper-small',
    this.sttLanguage = followApp,
    this.tts = TtsPreference.automatic,
    this.ttsVoice,
    this.sherpaVoices = const {},
    this.sherpaSpeakers = const {},
    this.ttsRate = 1.0,
    this.minSpeechMs = 200,
    this.vadThreshold = 0.5,
    this.spokenVersion = SpokenVersion.off,
    this.conversationMode = false,
    this.conversationAsked = false,
    this.conversationOfferPending = false,
    this.bargeIn = BargeInMode.keywords,
    this.keepModelLoaded = false,
    this.speakerRecognition = false,
  });

  /// [sttLanguage]: use the language chosen in the onboarding.
  static const followApp = 'app';

  /// [sttLanguage]: let Whisper detect the language.
  static const detect = 'auto';

  /// Offered tempo values.
  static const rates = [0.8, 1.0, 1.2, 1.5];

  /// Offered minimum speech durations (ms).
  static const minSpeechChoices = [100, 200, 300, 400];

  /// Offered VAD thresholds.
  static const thresholds = [0.3, 0.4, 0.5, 0.6, 0.7];

  /// Catalog id of the STT model (`whisper-small`, `parakeet-tdt-0.6b-v3`).
  final String sttModel;

  /// [followApp], [detect] or a fixed language (`de`, `fr`, `en`).
  final String sttLanguage;

  /// Speech output engine preference (K7 fallback in [TtsSelector]).
  final TtsPreference tts;

  /// Voice id of the system TTS; `null` = default voice of the language.
  final String? ttsVoice;

  /// Chosen offline voice per language (primary subtag → catalog id, WP66);
  /// a language without an entry uses the default voice of the catalog.
  final Map<String, String> sherpaVoices;

  /// Chosen speaker id per language for a multi-speaker offline voice
  /// (Kokoro, WP103); a language without entry uses the model's first
  /// speaker for it.
  final Map<String, String> sherpaSpeakers;

  /// Catalog id of the offline voice for [language] (primary subtag): the
  /// chosen one, else the catalog default; `null` for an unknown language.
  String? sherpaVoiceFor(
    String language, [
    SpeechModelCatalog catalog = SpeechModelCatalog.standard,
  ]) {
    final lang = language.split(RegExp('[-_]')).first.toLowerCase();
    return sherpaVoices[lang] ?? catalog.voiceFor(lang)?.id;
  }

  /// Speech rate (1.0 = normal).
  final double ttsRate;

  /// Minimum speech duration of the endpointing (ms).
  final int minSpeechMs;

  /// Silero speech probability threshold.
  final double vadThreshold;

  /// „Sprechfassung“ (WP41, WP55): whether the model writes a separate
  /// spoken version first and how it is protected after foreign content.
  /// More tokens, more natural speech.
  final SpokenVersion spokenVersion;

  /// „Weiter zuhören nach der Antwort“ (K23 d): after a spoken answer the
  /// microphone stays open for a follow-up window. Default off (M4, decision
  /// 2 of the maintainer).
  final bool conversationMode;

  /// The one-time question „Soll ich nach meinen Antworten standardmäßig
  /// weiter zuhören?“ was answered (or the setting was chosen otherwise).
  /// It is never asked again.
  final bool conversationAsked;

  /// The question is due: a request (possibly in the short-lived overlay
  /// engine) ended with an answer a follow-up would have suited. The main
  /// screen shows the card until it is answered. Persisted, because the
  /// overlay runs in its own engine.
  final bool conversationOfferPending;

  /// Barge-in during the speech output (K23 c). Only effective where a
  /// detector exists (WP58); default: keywords.
  final BargeInMode bargeIn;

  /// „Modell im Speicher halten“ (WP103): the recognizer and the offline
  /// voice stay loaded when the app is idle in the background or the
  /// overlay closes, so the next utterance starts without loading. Only
  /// memory pressure ([mayReleaseModels]) still frees them. Default off; the
  /// station mode (WP99) turns it on through [withStationDefaults].
  final bool keepModelLoaded;

  /// Speaker recognition (WP92a). Default off: without it (and without the
  /// model and an enrolled person) the pipeline does no extra work.
  final bool speakerRecognition;

  /// Copy for the station mode (WP99, not built yet): the models stay
  /// loaded (hook for WP99).
  VoiceSettings withStationDefaults() => copyWith(keepModelLoaded: true);

  /// The STT language for app language [appLanguage] (`null` = detect).
  String? effectiveLanguage(String appLanguage) => switch (sttLanguage) {
    followApp => appLanguage,
    detect => null,
    final fixed => fixed,
  };

  /// Endpointing limits with [minSpeechMs].
  EndpointConfig get endpoint =>
      EndpointConfig(minSpeech: Duration(milliseconds: minSpeechMs));

  /// Copy with changes; [clearVoice] resets [ttsVoice].
  VoiceSettings copyWith({
    String? sttModel,
    String? sttLanguage,
    TtsPreference? tts,
    String? ttsVoice,
    bool clearVoice = false,
    Map<String, String>? sherpaVoices,
    Map<String, String>? sherpaSpeakers,
    double? ttsRate,
    int? minSpeechMs,
    double? vadThreshold,
    SpokenVersion? spokenVersion,
    bool? conversationMode,
    bool? conversationAsked,
    bool? conversationOfferPending,
    BargeInMode? bargeIn,
    bool? keepModelLoaded,
    bool? speakerRecognition,
  }) => VoiceSettings(
    sttModel: sttModel ?? this.sttModel,
    sttLanguage: sttLanguage ?? this.sttLanguage,
    tts: tts ?? this.tts,
    ttsVoice: clearVoice ? null : ttsVoice ?? this.ttsVoice,
    sherpaVoices: sherpaVoices ?? this.sherpaVoices,
    sherpaSpeakers: sherpaSpeakers ?? this.sherpaSpeakers,
    ttsRate: ttsRate ?? this.ttsRate,
    minSpeechMs: minSpeechMs ?? this.minSpeechMs,
    vadThreshold: vadThreshold ?? this.vadThreshold,
    spokenVersion: spokenVersion ?? this.spokenVersion,
    conversationMode: conversationMode ?? this.conversationMode,
    conversationAsked: conversationAsked ?? this.conversationAsked,
    conversationOfferPending:
        conversationOfferPending ?? this.conversationOfferPending,
    bargeIn: bargeIn ?? this.bargeIn,
    keepModelLoaded: keepModelLoaded ?? this.keepModelLoaded,
    speakerRecognition: speakerRecognition ?? this.speakerRecognition,
  );

  /// JSON for the settings store.
  Map<String, Object?> toJson() => {
    'sttModel': sttModel,
    'sttLanguage': sttLanguage,
    'tts': tts.name,
    'ttsVoice': ?ttsVoice,
    if (sherpaVoices.isNotEmpty) 'sherpaVoices': sherpaVoices,
    if (sherpaSpeakers.isNotEmpty) 'sherpaSpeakers': sherpaSpeakers,
    'ttsRate': ttsRate,
    'minSpeechMs': minSpeechMs,
    'vadThreshold': vadThreshold,
    'spokenVersion': spokenVersion.name,
    'conversationMode': conversationMode,
    'conversationAsked': conversationAsked,
    'conversationOfferPending': conversationOfferPending,
    'bargeIn': bargeIn.name,
    'keepModelLoaded': keepModelLoaded,
    if (speakerRecognition) 'speakerRecognition': true,
  };

  /// Reads [json]; unknown or invalid values fall back to the defaults.
  static VoiceSettings fromJson(Map<String, Object?> json) {
    const d = VoiceSettings();
    T? pick<T>(String key, bool Function(T) valid) {
      final v = json[key];
      return v is T && valid(v) ? v : null;
    }

    // Migration (WP66): before, the one voice id could also be an offline
    // voice; it now belongs to the voice of its language.
    final legacy = pick<String>('ttsVoice', (v) => v.isNotEmpty);
    final legacyModel = legacy == null
        ? null
        : SpeechModelCatalog.standard.byId(legacy);
    final legacyOffline = legacyModel?.kind == SpeechModelKind.tts
        ? legacyModel
        : null;
    final voices = <String, String>{};
    final raw = json['sherpaVoices'];
    if (raw is Map) {
      for (final MapEntry(:key, :value) in raw.entries) {
        final model = value is String
            ? SpeechModelCatalog.standard.byId(value)
            : null;
        if (key is String &&
            model != null &&
            model.kind == SpeechModelKind.tts &&
            model.languages.contains(key)) {
          voices[key] = model.id;
        }
      }
    }
    final speakers = <String, String>{};
    final rawSpeakers = json['sherpaSpeakers'];
    if (rawSpeakers is Map) {
      for (final MapEntry(:key, :value) in rawSpeakers.entries) {
        if (key is! String || value is! String) continue;
        final known = SpeechModelCatalog.standard.models.any(
          (m) => m.speakersFor(key).any((s) => s.id == value),
        );
        if (known) speakers[key] = value;
      }
    }
    if (legacyOffline != null) {
      voices.putIfAbsent(legacyOffline.languages.first, () => legacyOffline.id);
    }

    return VoiceSettings(
      sttModel:
          pick<String>(
            'sttModel',
            (v) =>
                SpeechModelCatalog.standard.byId(v)?.kind ==
                SpeechModelKind.stt,
          ) ??
          d.sttModel,
      sttLanguage:
          pick<String>(
            'sttLanguage',
            (v) => const {followApp, detect, 'de', 'fr', 'en'}.contains(v),
          ) ??
          d.sttLanguage,
      tts: TtsPreference.values.asNameMap()[json['tts']] ?? d.tts,
      ttsVoice: legacyOffline == null ? legacy : null,
      sherpaVoices: Map.unmodifiable(voices),
      sherpaSpeakers: Map.unmodifiable(speakers),
      ttsRate:
          pick<num>('ttsRate', (v) => v >= 0.5 && v <= 2)?.toDouble() ??
          d.ttsRate,
      minSpeechMs:
          pick<int>('minSpeechMs', (v) => v >= 50 && v <= 1000) ??
          d.minSpeechMs,
      vadThreshold:
          pick<num>('vadThreshold', (v) => v > 0 && v < 1)?.toDouble() ??
          d.vadThreshold,
      // Migration (WP55): the former switch „twoVersions“ becomes the level
      // `protected` (its behaviour) or `off`.
      spokenVersion:
          SpokenVersion.values.asNameMap()[json['spokenVersion']] ??
          (json['twoVersions'] == true
              ? SpokenVersion.protected
              : d.spokenVersion),
      conversationMode:
          pick<bool>('conversationMode', (_) => true) ?? d.conversationMode,
      conversationAsked:
          pick<bool>('conversationAsked', (_) => true) ?? d.conversationAsked,
      conversationOfferPending:
          pick<bool>('conversationOfferPending', (_) => true) ??
          d.conversationOfferPending,
      bargeIn: BargeInMode.values.asNameMap()[json['bargeIn']] ?? d.bargeIn,
      keepModelLoaded:
          pick<bool>('keepModelLoaded', (_) => true) ?? d.keepModelLoaded,
      speakerRecognition:
          pick<bool>('speakerRecognition', (_) => true) ?? d.speakerRecognition,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceSettings &&
      other.sttModel == sttModel &&
      other.sttLanguage == sttLanguage &&
      other.tts == tts &&
      other.ttsVoice == ttsVoice &&
      _sameVoices(other.sherpaVoices, sherpaVoices) &&
      _sameVoices(other.sherpaSpeakers, sherpaSpeakers) &&
      other.ttsRate == ttsRate &&
      other.minSpeechMs == minSpeechMs &&
      other.vadThreshold == vadThreshold &&
      other.spokenVersion == spokenVersion &&
      other.conversationMode == conversationMode &&
      other.conversationAsked == conversationAsked &&
      other.conversationOfferPending == conversationOfferPending &&
      other.bargeIn == bargeIn &&
      other.keepModelLoaded == keepModelLoaded &&
      other.speakerRecognition == speakerRecognition;

  @override
  int get hashCode => Object.hash(
    sttModel,
    sttLanguage,
    tts,
    ttsVoice,
    Object.hashAllUnordered([
      for (final e in sherpaVoices.entries) Object.hash(e.key, e.value),
    ]),
    Object.hashAllUnordered([
      for (final e in sherpaSpeakers.entries) Object.hash(e.key, e.value),
    ]),
    ttsRate,
    minSpeechMs,
    vadThreshold,
    spokenVersion,
    conversationMode,
    conversationAsked,
    conversationOfferPending,
    bargeIn,
    keepModelLoaded,
    speakerRecognition,
  );
}

bool _sameVoices(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

/// The offline voice that really speaks (WP66), shared by the settings and
/// the speech output: [chosen] if it is among [available] (loaded voices of
/// the language, in catalog order), else the first loaded one, else `null`.
String? effectiveSherpaVoice({
  required String? chosen,
  required Iterable<String> available,
}) {
  if (chosen != null && available.contains(chosen)) return chosen;
  return available.isEmpty ? null : available.first;
}
