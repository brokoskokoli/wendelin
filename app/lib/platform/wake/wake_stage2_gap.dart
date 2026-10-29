import 'package:wendelin_voice/wendelin_voice.dart';

import 'wake_shadow_cost.dart';

/// Why stage 2 cannot decide (WP171). While it is set, every candidate that
/// verifier B cannot judge is rejected (fail closed) or decided by the
/// recognizer alone.
enum WakeStage2Gap {
  /// No enrolled sequences for verifier B and no recognizer installed
  /// (neither Parakeet nor Whisper): `wake-verify error=model_missing`.
  modelMissing,

  /// A recognizer is installed (fallback), but a learned voice has no
  /// sequences for verifier B: only the fallback decides, which can drop
  /// real calls. The wake word has to be enrolled again.
  noSequences;

  /// The reason as logged and sent to Kotlin.
  String get logName => switch (this) {
    modelMissing => 'model_missing',
    noSequences => 'no_sequences',
  };
}

/// The user's configuration for wake-word stage 2 verification (WP177).
final class WakeStage2Settings {
  /// Creates the settings.
  const WakeStage2Settings({this.verifierB = true, this.recognizer = false});

  /// Whether verifier B (template matching against enrolled voices) is enabled.
  final bool verifierB;

  /// Whether speech recognition (Parakeet or Whisper) is enabled.
  final bool recognizer;

  /// Whether stage 2 verification is active at all.
  bool get active => verifierB || recognizer;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WakeStage2Settings &&
          runtimeType == other.runtimeType &&
          verifierB == other.verifierB &&
          recognizer == other.recognizer;

  @override
  int get hashCode => Object.hash(verifierB, recognizer);

  @override
  String toString() =>
      'WakeStage2Settings(b: $verifierB, recognizer: $recognizer)';
}

/// The rule for [WakeStage2Gap] (WP171, WP177):
///
/// - When neither B nor recognizer is active: no gap (stage 2 is off).
/// - When recognizer is active: needs an installed recognition model
///   (`recognizerInstalled`). If missing: [WakeStage2Gap.modelMissing].
/// - When verifier B is active:
///   - If voices are enrolled and any has no sequences: [WakeStage2Gap.noSequences]
///     (or [WakeStage2Gap.modelMissing] if fallback recognizer is also active but missing).
WakeStage2Gap? wakeStage2GapOf({
  required bool anyVoice,
  required bool anyWithoutSequences,
  required bool verifierB,
  bool? recognizer,
  required bool recognizerInstalled,
}) {
  if (!anyVoice) return null;
  if (!verifierB && recognizer == false) return null;
  final needsFallback = verifierB ? anyWithoutSequences : anyVoice;
  final needsModel = (recognizer ?? false) || needsFallback;
  if (needsModel && !recognizerInstalled) {
    return WakeStage2Gap.modelMissing;
  }
  if (verifierB && anyWithoutSequences) {
    return WakeStage2Gap.noSequences;
  }
  return null;
}

/// Counts what the recognizer fallback of stage 2 costs (WP171): model loads
/// (each one is ~1 GB of RAM and seconds of CPU) and checks. The model stays
/// loaded for `idleRelease` after the last check, so loads should be far
/// fewer than checks; `wake-alive` logs both per hour.
final class WakeFallbackStats {
  /// Model loads of Parakeet or Whisper for stage 2.
  int loads = 0;

  /// Clips that verifier B handed to the recognizer (or that it checked
  /// alone when B is off).
  int checks = 0;

  /// WP171: developer-mode shadow detector, compute time per window.
  final shadow = WakeShadowCost();

  /// Starts counting anew (a new listener).
  void reset() {
    loads = 0;
    checks = 0;
    shadow.reset();
  }
}

/// Whisper fallbacks of stage 2; like the engine
/// (`DeviceRecognizerEngines.checkInstalled`) they count only together with
/// the Silero VAD.
final _stage2Whisper = [
  SpeechModelCatalog.whisperSmall,
  SpeechModelCatalog.whisperBase,
];

/// Whether stage 2 has a recognizer according to the install [states]:
/// Parakeet (needs only its own files, `wakeParakeetFiles`) or Whisper
/// small/base *with* Silero VAD; `null` while the states are not read yet
/// (and nothing is installed), so nothing is claimed at start.
bool? wakeStage2RecognizerInstalled(Map<String, ModelState> states) {
  ModelPhase? phase(SpeechModel m) => states[m.id]?.phase;
  bool unread(SpeechModel m) {
    final p = phase(m);
    return p == null || p == ModelPhase.unknown;
  }

  if (phase(SpeechModelCatalog.parakeetV3) == ModelPhase.installed) {
    return true;
  }
  final vad = SpeechModelCatalog.sileroVad;
  final vadInstalled = phase(vad) == ModelPhase.installed;
  var read = !unread(SpeechModelCatalog.parakeetV3);
  for (final m in _stage2Whisper) {
    if (phase(m) == ModelPhase.installed && vadInstalled) return true;
    if (unread(m)) read = false;
  }
  if (unread(vad)) read = false;
  return read ? false : null;
}
