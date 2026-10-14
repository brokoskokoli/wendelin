import 'package:meta/meta.dart';

import '../pipeline/endpointer.dart';
import '../pipeline/voice_pipeline_config.dart';
import '../tts/tts_selector.dart';

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
    this.ttsRate = 1.0,
    this.minSpeechMs = 200,
    this.vadThreshold = 0.5,
    this.stopClosesOverlay = true,
    this.twoVersions = false,
    this.conversationMode = false,
    this.conversationAsked = false,
    this.conversationOfferPending = false,
    this.bargeIn = BargeInMode.keywords,
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

  /// Whisper model id (`whisper-base`, `whisper-small`).
  final String sttModel;

  /// [followApp], [detect] or a fixed language (`de`, `fr`, `en`).
  final String sttLanguage;

  /// Speech output engine preference (K7 fallback in [TtsSelector]).
  final TtsPreference tts;

  /// Voice id (system or sherpa); `null` = default voice of the language.
  final String? ttsVoice;

  /// Speech rate (1.0 = normal).
  final double ttsRate;

  /// Minimum speech duration of the endpointing (ms).
  final int minSpeechMs;

  /// Silero speech probability threshold.
  final double vadThreshold;

  /// A spoken „Stopp“ in the assistant overlay closes it (WP31, B5).
  final bool stopClosesOverlay;

  /// „Antwort in zwei Fassungen“ (WP41, stage 2): the model writes a
  /// separate spoken version first. More tokens, more natural speech.
  final bool twoVersions;

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
    double? ttsRate,
    int? minSpeechMs,
    double? vadThreshold,
    bool? stopClosesOverlay,
    bool? twoVersions,
    bool? conversationMode,
    bool? conversationAsked,
    bool? conversationOfferPending,
    BargeInMode? bargeIn,
  }) => VoiceSettings(
    sttModel: sttModel ?? this.sttModel,
    sttLanguage: sttLanguage ?? this.sttLanguage,
    tts: tts ?? this.tts,
    ttsVoice: clearVoice ? null : ttsVoice ?? this.ttsVoice,
    ttsRate: ttsRate ?? this.ttsRate,
    minSpeechMs: minSpeechMs ?? this.minSpeechMs,
    vadThreshold: vadThreshold ?? this.vadThreshold,
    stopClosesOverlay: stopClosesOverlay ?? this.stopClosesOverlay,
    twoVersions: twoVersions ?? this.twoVersions,
    conversationMode: conversationMode ?? this.conversationMode,
    conversationAsked: conversationAsked ?? this.conversationAsked,
    conversationOfferPending:
        conversationOfferPending ?? this.conversationOfferPending,
    bargeIn: bargeIn ?? this.bargeIn,
  );

  /// JSON for the settings store.
  Map<String, Object?> toJson() => {
    'sttModel': sttModel,
    'sttLanguage': sttLanguage,
    'tts': tts.name,
    'ttsVoice': ?ttsVoice,
    'ttsRate': ttsRate,
    'minSpeechMs': minSpeechMs,
    'vadThreshold': vadThreshold,
    'stopClosesOverlay': stopClosesOverlay,
    'twoVersions': twoVersions,
    'conversationMode': conversationMode,
    'conversationAsked': conversationAsked,
    'conversationOfferPending': conversationOfferPending,
    'bargeIn': bargeIn.name,
  };

  /// Reads [json]; unknown or invalid values fall back to the defaults.
  static VoiceSettings fromJson(Map<String, Object?> json) {
    const d = VoiceSettings();
    T? pick<T>(String key, bool Function(T) valid) {
      final v = json[key];
      return v is T && valid(v) ? v : null;
    }

    return VoiceSettings(
      sttModel:
          pick<String>('sttModel', (v) => v.startsWith('whisper-')) ??
          d.sttModel,
      sttLanguage:
          pick<String>(
            'sttLanguage',
            (v) => const {followApp, detect, 'de', 'fr', 'en'}.contains(v),
          ) ??
          d.sttLanguage,
      tts: TtsPreference.values.asNameMap()[json['tts']] ?? d.tts,
      ttsVoice: pick<String>('ttsVoice', (v) => v.isNotEmpty),
      ttsRate:
          pick<num>('ttsRate', (v) => v >= 0.5 && v <= 2)?.toDouble() ??
          d.ttsRate,
      minSpeechMs:
          pick<int>('minSpeechMs', (v) => v >= 50 && v <= 1000) ??
          d.minSpeechMs,
      vadThreshold:
          pick<num>('vadThreshold', (v) => v > 0 && v < 1)?.toDouble() ??
          d.vadThreshold,
      stopClosesOverlay:
          pick<bool>('stopClosesOverlay', (_) => true) ?? d.stopClosesOverlay,
      twoVersions: pick<bool>('twoVersions', (_) => true) ?? d.twoVersions,
      conversationMode:
          pick<bool>('conversationMode', (_) => true) ?? d.conversationMode,
      conversationAsked:
          pick<bool>('conversationAsked', (_) => true) ?? d.conversationAsked,
      conversationOfferPending:
          pick<bool>('conversationOfferPending', (_) => true) ??
          d.conversationOfferPending,
      bargeIn: BargeInMode.values.asNameMap()[json['bargeIn']] ?? d.bargeIn,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceSettings &&
      other.sttModel == sttModel &&
      other.sttLanguage == sttLanguage &&
      other.tts == tts &&
      other.ttsVoice == ttsVoice &&
      other.ttsRate == ttsRate &&
      other.minSpeechMs == minSpeechMs &&
      other.vadThreshold == vadThreshold &&
      other.stopClosesOverlay == stopClosesOverlay &&
      other.twoVersions == twoVersions &&
      other.conversationMode == conversationMode &&
      other.conversationAsked == conversationAsked &&
      other.conversationOfferPending == conversationOfferPending &&
      other.bargeIn == bargeIn;

  @override
  int get hashCode => Object.hash(
    sttModel,
    sttLanguage,
    tts,
    ttsVoice,
    ttsRate,
    minSpeechMs,
    vadThreshold,
    stopClosesOverlay,
    twoVersions,
    conversationMode,
    conversationAsked,
    conversationOfferPending,
    bargeIn,
  );
}
