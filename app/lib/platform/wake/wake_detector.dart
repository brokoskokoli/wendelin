import 'package:wendelin_voice/wendelin_voice.dart';

/// Which stage 1 detection listens for the wake word (WP129).
enum WakeDetector {
  /// Personal templates (K31): similarity of the feature window to the
  /// recorded „Wendelin“.
  templates,

  /// The trained classifier (`wake-classifier-wendelin`, K105).
  model,
}

/// The setting „Erkennung“: `auto` follows the place (phone: templates,
/// station: classifier), the others fix it.
enum WakeDetectorChoice {
  /// Phone: templates, station: classifier (default).
  auto,

  /// Always templates.
  templates,

  /// Always the classifier.
  model;

  /// Parses the stored value; unknown values fall back to [auto].
  static WakeDetectorChoice parse(Object? value) {
    for (final c in values) {
      if (c.name == value) return c;
    }
    return auto;
  }

  /// The detection for a run on the [station] or on the phone.
  WakeDetector resolve({required bool station}) => switch (this) {
    WakeDetectorChoice.templates => WakeDetector.templates,
    WakeDetectorChoice.model => WakeDetector.model,
    WakeDetectorChoice.auto =>
      station ? WakeDetector.model : WakeDetector.templates,
  };
}

/// The score band of the classifier for the place (limits: catalog).
WakeScoreBand wakeBandFor({required bool station}) =>
    station ? WakeClassifierRules.station : WakeClassifierRules.phone;
