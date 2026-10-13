import 'package:meta/meta.dart';

import '../io/text_to_speech.dart';

/// Which speech output the user chose in the settings.
enum TtsPreference {
  /// System voice if installed, otherwise sherpa-onnx (default, K7).
  automatic,

  /// Always the system voice (falls back to sherpa-onnx if it is missing).
  system,

  /// Always the offline sherpa-onnx voice (falls back to the system voice
  /// if no sherpa voice is downloaded).
  sherpa,
}

/// The engine that was chosen.
enum TtsEngine {
  /// Android/iOS system TTS.
  system,

  /// sherpa-onnx (offline voice model).
  sherpa,

  /// No speech output available: answers appear only on the screen.
  none,
}

/// Result of [TtsSelector.select].
@immutable
final class TtsSelection {
  /// Creates a result.
  const TtsSelection({
    required this.engine,
    required this.tts,
    this.fallback = false,
  });

  /// Chosen engine.
  final TtsEngine engine;

  /// The engine instance; `null` for [TtsEngine.none].
  final TextToSpeech? tts;

  /// Whether the preferred engine was unavailable and the other one is
  /// used (shown as a hint in the settings).
  final bool fallback;

  @override
  String toString() => 'TtsSelection(${engine.name}, fallback: $fallback)';
}

/// Chooses the speech output (K7: ohne Google-Dienste).
///
/// By default the system voice is used when one is installed; otherwise the
/// offline sherpa-onnx voice. The user preference overrides the order; if
/// the preferred engine is unavailable, the other one is used, so the
/// assistant only goes silent when neither works.
final class TtsSelector {
  /// Creates a selector; [sherpa] is `null` until a voice is set up.
  TtsSelector({
    required this.system,
    this.sherpa,
    TtsPreference Function()? preference,
  }) : _preference = preference ?? (() => TtsPreference.automatic);

  /// System TTS.
  final TextToSpeech system;

  /// sherpa-onnx TTS, if configured.
  final TextToSpeech? sherpa;

  final TtsPreference Function() _preference;

  /// Picks the engine for the next answer in [language] (BCP 47).
  ///
  /// With [language], an engine that lists voices but none for that
  /// language counts as unavailable (e.g. sherpa with only a German voice
  /// for a French answer). An engine without a voice list is trusted.
  Future<TtsSelection> select({String? language}) async {
    final preference = _preference();
    final preferSherpa = preference == TtsPreference.sherpa;
    final order = preferSherpa
        ? [(TtsEngine.sherpa, sherpa), (TtsEngine.system, system)]
        : [(TtsEngine.system, system), (TtsEngine.sherpa, sherpa)];
    for (final (i, (engine, tts)) in order.indexed) {
      if (tts == null) continue;
      if (await _available(tts) && await _speaks(tts, language)) {
        // Only an explicit preference makes the second engine a fallback;
        // automatic mode prefers the system voice by definition.
        final fallback = i > 0 && preference != TtsPreference.automatic;
        return TtsSelection(engine: engine, tts: tts, fallback: fallback);
      }
    }
    return const TtsSelection(engine: TtsEngine.none, tts: null);
  }

  /// The engine for the next answer in [language] (`null` = text only).
  Future<TextToSpeech?> current([String? language]) async =>
      (await select(language: language)).tts;

  static Future<bool> _speaks(TextToSpeech tts, String? language) async {
    if (language == null) return true;
    final lang = _primary(language);
    try {
      final voices = await tts.voices();
      return voices.isEmpty || voices.any((v) => _primary(v.language) == lang);
    } on Object {
      return false; // treated like an unavailable engine
    }
  }

  static String _primary(String tag) =>
      tag.split(RegExp('[-_]')).first.toLowerCase();

  static Future<bool> _available(TextToSpeech tts) async {
    try {
      return await tts.isAvailable;
    } on Object {
      return false;
    }
  }
}
