import 'package:meta/meta.dart';

/// Sensitivity levels of the settings (low = few false triggers).
enum WakeSensitivity {
  /// Strict thresholds.
  low,

  /// Default.
  medium,

  /// Lenient thresholds (more candidates for the second stage).
  high,
}

/// One keyword the wake word engine listens for (`wake`, `stop`).
@immutable
final class KeywordSpec {
  /// Creates a spec. [variants] are pronunciations as phoneme sequences
  /// (e.g. `W EH1 N D AH0 L IH0 N`); [thresholds] maps every sensitivity to
  /// a detection threshold.
  const KeywordSpec({
    required this.id,
    required this.variants,
    required this.thresholds,
    this.boost = 2.0,
  });

  /// The wake word „Wendelin“ (English phoneme approximation, see the spike
  /// notes). Thresholds from the WP58 pilot table; to be re-set with real
  /// recordings.
  static const wendelin = KeywordSpec(
    id: 'wake',
    variants: ['W EH1 N D AH0 L IH0 N'],
    thresholds: {
      WakeSensitivity.low: 0.98,
      WakeSensitivity.medium: 0.9,
      WakeSensitivity.high: 0.6,
    },
  );

  /// Id reported in a hit (`wake`, `stop`).
  final String id;

  /// Pronunciation variants as space separated phonemes.
  final List<String> variants;

  /// Threshold per sensitivity (all levels required).
  final Map<WakeSensitivity, double> thresholds;

  /// Boost score of the sherpa keywords file.
  final double boost;

  /// Threshold for [level].
  double thresholdFor(WakeSensitivity level) => thresholds[level]!;
}

/// The sherpa-onnx keywords file for [keywords] at [level]: one line per
/// pronunciation variant, `PHONEMES :boost #threshold @ID`.
String keywordsFile(List<KeywordSpec> keywords, WakeSensitivity level) {
  final b = StringBuffer();
  for (final k in keywords) {
    for (final v in k.variants) {
      b.writeln('$v :${k.boost} #${k.thresholdFor(level)} @${k.id}');
    }
  }
  return b.toString();
}
