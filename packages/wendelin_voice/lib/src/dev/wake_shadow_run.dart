import '../wake/wake_word_engine.dart';
import 'dev_archive.dart';

/// WP171: template margin (similarity minus threshold) from which a window
/// counts for a near miss. The template similarity is a margin on the scale
/// of the personal thresholds (0.40..0.85): -0.05 collects the windows that
/// are close under the limit without collecting speech in general (speech
/// alone sits at the limit 0.40 about 88 candidates per hour, see
/// [devNearMissFrom]); `0` is the candidate rule itself.
const shadowTemplateNearMargin = 0.05;

/// How far before a candidate its case looks for the values of both
/// recognizers (1.5 s).
const shadowLeadSamples = 24000;

/// Hands [sink] to [engine] (WP171): the windows of both recognizers, or for
/// an engine that only reports the classifier score (WP155) a window with
/// the model alone.
void attachWindowSink(
  WakeWordEngine engine,
  void Function(WakeWindowScores window) sink,
) {
  if (engine is ShadowScoringWakeEngine) {
    engine.windowSink = sink;
  } else if (engine is ScoringWakeEngine) {
    engine.scoreSink = (end, score) => sink((
      endSample: end,
      model: score,
      similarity: null,
      threshold: null,
      margin: null,
      primaryModel: true,
    ));
  }
}

/// Highest values of both recognizers over some windows.
final class ShadowPeaks {
  /// Highest classifier score, and the stream position of that window.
  double? modelPeak;

  /// See [modelPeak].
  int? modelEnd;

  /// Largest template margin, the raw similarity and the threshold of that
  /// window's set (margins are comparable between sets, similarities not).
  double? margin, similarity, threshold;

  /// Stream position of the largest margin.
  int? marginEnd;

  /// Whether the **model** was the deciding recognizer (last window).
  bool primaryModel = true;

  /// No window rated yet.
  bool get isEmpty => modelPeak == null && margin == null;

  /// Adds a window.
  void add(WakeWindowScores w) {
    primaryModel = w.primaryModel;
    final m = w.model;
    if (m != null && (modelPeak == null || m >= modelPeak!)) {
      modelPeak = m;
      modelEnd = w.endSample;
    }
    final g = w.margin;
    if (g != null && (margin == null || g >= margin!)) {
      margin = g;
      similarity = w.similarity;
      threshold = w.threshold;
      marginEnd = w.endSample;
    }
  }

  /// The model reached the candidate limit [above].
  bool wouldModel(double above) => modelPeak != null && modelPeak! >= above;

  /// A template set reached its threshold.
  bool get wouldTemplates => margin != null && margin! >= 0;

  /// `model`, `templates`, `both` or `none`.
  String would(double above) => switch ((wouldModel(above), wouldTemplates)) {
    (true, true) => 'both',
    (true, false) => 'model',
    (false, true) => 'templates',
    _ => 'none',
  };
}

/// One finished run: a near miss or a "would have triggered".
final class ShadowCase {
  /// Creates the result.
  const ShadowCase({
    required this.peaks,
    required this.clipEnd,
    required this.ms,
  });

  /// Values of both recognizers over the run.
  final ShadowPeaks peaks;

  /// Stream position the clip is centered on (the stronger peak).
  final int clipEnd;

  /// Length of the run in ms.
  final int ms;
}

/// Turns the window values of **both** stage 1 recognizers into one case
/// per utterance (WP171, replaces the classifier-only tracker of WP155 for
/// the listener). A run starts with a relevant window of either recognizer
/// (model from [from], template margin from [shadowTemplateNearMargin]) and
/// ends after [gap] samples without one. It is void when the deciding
/// recognizer reached its candidate limit (a real candidate: its case is the
/// one [WakeWordListener] opens) or when a candidate was reported with
/// [markCandidate] (hold, other recognizer). The shadow reaching its limit
/// keeps the run: `shadow-would`. After a case the next one is accepted
/// [minSpacing] later, for both recognizers together.
final class WakeShadowRun {
  /// Creates the run. [above]: candidate limit of the model (verify limit).
  WakeShadowRun({
    required this.above,
    this.from = devNearMissFrom,
    this.gap = 16000,
    this.minSpacing = 80000,
    this.candidateGuard = 32000,
    this.ringSpan = 64000,
  });

  /// Candidate limit of the classifier.
  final double above;

  /// Floor of a classifier near miss.
  final double from;

  /// Samples without a relevant window that end a run (1 s).
  final int gap;

  /// Samples between two cases (5 s).
  final int minSpacing;

  /// A run whose peak lies this close to a candidate belongs to it (2 s).
  final int candidateGuard;

  /// How far back [peaksAround] can look (4 s).
  final int ringSpan;

  final _ring = <WakeWindowScores>[];
  ShadowPeaks _peaks = ShadowPeaks();
  bool _open = false, _void = false;
  int _start = 0, _lastRelevant = 0, _lastSent = -1 << 40;
  int _lastCandidate = -1 << 40;

  /// Forgets everything (new stream).
  void reset() {
    _ring.clear();
    _open = false;
    _void = false;
    _lastSent = -1 << 40;
    _lastCandidate = -1 << 40;
  }

  /// A real candidate at stream position [end]: its case is the archive
  /// entry, the open run (and one right around it) is void.
  void markCandidate(int end) {
    _lastCandidate = end;
    if (_open) _void = true;
  }

  /// A candidate at [end]: marks it and returns the values around it
  /// (`null` on a failure, never into the voice path).
  ShadowPeaks? candidate(int end) {
    try {
      markCandidate(end);
      return peaksAround(end - shadowLeadSamples);
    } on Object {
      return null;
    }
  }

  /// Values of both recognizers over the windows at or after [fromEnd].
  ShadowPeaks peaksAround(int fromEnd) {
    final p = ShadowPeaks();
    for (final w in _ring) {
      if (w.endSample >= fromEnd) p.add(w);
    }
    return p;
  }

  /// A window; returns the case of a run that just ended, else `null`.
  ShadowCase? onWindow(WakeWindowScores w) {
    _ring.add(w);
    while (w.endSample - _ring.first.endSample > ringSpan) {
      _ring.removeAt(0);
    }
    final end = w.endSample;
    ShadowCase? done;
    if (_open && end - _lastRelevant >= gap) done = _close();
    final m = w.model, g = w.margin;
    final relevant =
        (m != null && m >= from) ||
        (g != null && g >= -shadowTemplateNearMargin);
    if (!_open) {
      if (!relevant) return done;
      _open = true;
      _void = false;
      _start = end;
      _peaks = ShadowPeaks();
    }
    _peaks.add(w);
    if (relevant) _lastRelevant = end;
    final primaryWould = w.primaryModel
        ? m != null && m >= above
        : g != null && g >= 0;
    if (primaryWould) _void = true;
    return done;
  }

  ShadowCase? _close() {
    _open = false;
    final p = _peaks;
    // The stronger peak above its own floor centers the clip.
    final fm = p.modelPeak == null ? -1.0 : p.modelPeak! - from;
    final fg = p.margin == null ? -1.0 : p.margin! + shadowTemplateNearMargin;
    final clipEnd = (fm >= fg ? p.modelEnd : p.marginEnd) ?? _lastRelevant;
    if (_void ||
        (clipEnd - _lastCandidate).abs() <= candidateGuard ||
        clipEnd - _lastSent < minSpacing) {
      return null;
    }
    _lastSent = clipEnd;
    return ShadowCase(
      peaks: p,
      clipEnd: clipEnd,
      ms: (_lastRelevant - _start) ~/ 16,
    );
  }
}
