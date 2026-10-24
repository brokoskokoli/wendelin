import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../io/audio_input.dart';
import '../models/wake_classifier_catalog.dart';
import 'level_normalize.dart';
import 'wake_feature_extractor.dart';
import 'wake_templates.dart';
import 'wake_verifier.dart';
import 'wake_verifier_b_mu.g.dart';

export 'wake_verifier_b_mu.g.dart'
    show wakeVerifierBFeatureVersion, wakeVerifierBMuIsPlaceholder;

/// Values per embedding frame.
const verifierBFrameSize = 96;

/// `mu` of verifier B (96 values), decoded from the generated constant.
final Float32List wakeVerifierBMu = () {
  final bytes = Uint8List.fromList(base64Decode(wakeVerifierBMuBase64));
  if (bytes.length != verifierBFrameSize * 4) {
    throw StateError('mu hat ${bytes.length ~/ 4} statt $verifierBFrameSize');
  }
  return bytes.buffer.asFloat32List(0, verifierBFrameSize);
}();

/// An embedding sequence ready for the comparison: every frame has `mu`
/// subtracted and is scaled to length 1 (an all-zero frame stays zero).
final class VerifierBSequence {
  /// Centers and normalizes [raw] (`frames` × 96, flattened).
  factory VerifierBSequence.prepare(Float32List raw, Float32List mu) {
    if (raw.length % verifierBFrameSize != 0 ||
        mu.length != verifierBFrameSize) {
      throw ArgumentError('Länge ${raw.length} / mu ${mu.length} passt nicht');
    }
    final n = raw.length ~/ verifierBFrameSize;
    final out = Float32List(raw.length);
    for (var f = 0; f < n; f++) {
      final o = f * verifierBFrameSize;
      var sum = 0.0;
      for (var i = 0; i < verifierBFrameSize; i++) {
        final v = raw[o + i] - mu[i];
        out[o + i] = v;
        sum += v * v;
      }
      // v / (|v| + 1e-9) like the measurement (a zero frame stays zero).
      final inv = 1 / (math.sqrt(sum) + 1e-9);
      for (var i = 0; i < verifierBFrameSize; i++) {
        out[o + i] *= inv;
      }
    }
    return VerifierBSequence._(out, n);
  }

  const VerifierBSequence._(this.values, this.frames);

  /// Prepared frames, flattened.
  final Float32List values;

  /// Number of frames.
  final int frames;
}

/// Score of the live sequence [live] against one template [tpl]: the cosine
/// per frame pair averaged over the template length, maximum over the
/// offset of the template in the live sequence. `-1` when the live sequence
/// is shorter than the template (nothing to compare: counts as rejected).
double verifierBTemplateScore(VerifierBSequence live, VerifierBSequence tpl) {
  final m = tpl.frames;
  if (m == 0 || live.frames < m) return -1;
  var best = -double.infinity;
  for (var off = 0; off + m <= live.frames; off++) {
    var sum = 0.0;
    for (var j = 0; j < m; j++) {
      final a = (off + j) * verifierBFrameSize;
      final b = j * verifierBFrameSize;
      var dot = 0.0;
      for (var i = 0; i < verifierBFrameSize; i++) {
        dot += live.values[a + i] * tpl.values[b + i];
      }
      sum += dot;
    }
    best = math.max(best, sum / m);
  }
  return best;
}

/// Score of [live] against the [templates] of one word: the mean of the best
/// [topK] template scores. With fewer than [topK] templates the mean of all
/// of them (a short enrollment still decides). Templates longer than [live]
/// are ignored; `-1` when no usable template is left (rejected).
double verifierBScore(
  VerifierBSequence live,
  List<VerifierBSequence> templates, {
  int topK = WakeClassifierRules.verifierBTopK,
}) {
  final scores = [
    for (final t in templates)
      if (t.frames > 0 && t.frames <= live.frames)
        verifierBTemplateScore(live, t),
  ]..sort((a, b) => b.compareTo(a));
  if (scores.isEmpty) return -1;
  final k = math.min(topK, scores.length);
  var sum = 0.0;
  for (var i = 0; i < k; i++) {
    sum += scores[i];
  }
  return sum / k;
}

/// Python `round` (halves go to the even number) of `value / 160`, times 160:
/// the live cut starts on a multiple of 160 samples.
int verifierBAlign(int value) {
  final q = value ~/ 160, r = value - q * 160;
  final up = r > 80 || (r == 80 && q.isOdd);
  return (up ? q + 1 : q) * 160;
}

/// Bounds `(from, to)` of the live cut for the decision window ending at
/// [endSample] (may lie outside the signal; the clip is filled with zeros
/// there): 1.9 s before and 0.85 s after the aligned end, 44 000 samples.
({int from, int to}) verifierBLiveBounds(int endSample) {
  final e = verifierBAlign(endSample);
  return (
    from: e - durationToSamples(WakeClassifierRules.verifierBBefore),
    to: e + durationToSamples(WakeClassifierRules.verifierBAfter),
  );
}

/// The live clip: [verifierBLiveBounds] of [pcm], zeros outside the signal,
/// scaled to the peak [WakeClassifierRules.verifyPeak] (when it has any
/// signal at all).
Int16List verifierBLiveClip(Int16List pcm, int endSample) {
  final (:from, :to) = verifierBLiveBounds(endSample);
  final out = Int16List(to - from);
  final lo = math.max(0, from), hi = math.min(pcm.length, to);
  if (hi > lo) out.setRange(lo - from, hi - from, pcm, lo);
  return normalizePeak(out, target: WakeClassifierRules.verifyPeak, minPeak: 1);
}

/// Bounds `(from, to)` of the template cut before the trim, for speech from
/// [startSeconds] to [endSeconds] in a recording of [length] samples:
/// `trunc((start - 0.12) * 16000)` and `trunc((end + 0.20) * 16000)` in
/// floating point (towards zero, not rounded), limited to the recording.
({int from, int to}) verifierBTemplateBounds(
  int length,
  double startSeconds,
  double endSeconds,
) => (
  from: math.max(
    0,
    ((startSeconds - WakeClassifierRules.verifierBTemplateLeadSeconds) *
            AudioInput.sampleRate)
        .truncate(),
  ),
  to: math.min(
    length,
    ((endSeconds + WakeClassifierRules.verifierBTemplateTailSeconds) *
            AudioInput.sampleRate)
        .truncate(),
  ),
);

/// Bounds `(from, to)` of the template clip in [length] samples of
/// recording: the cut of [verifierBTemplateBounds] for the speech from
/// [speechStart] to [speechEnd], no trim. A cut shorter than
/// [WakeClassifierRules.verifierBMinTemplateSamples] is padded
/// symmetrically (the odd sample at the end) with the real audio around it,
/// never with zeros; if the recording lacks audio on one side the window
/// moves to the other. `null` when the recording itself is shorter than the
/// minimum, the speech lies outside it, or the cut is longer than
/// [WakeClassifierRules.verifierBMaxTemplateSamples] (not measured).
({int from, int to})? verifierBTemplateWindow(
  int length,
  int speechStart,
  int speechEnd,
) {
  final min = WakeClassifierRules.verifierBMinTemplateSamples;
  final cut = verifierBTemplateBounds(
    length,
    speechStart / AudioInput.sampleRate,
    speechEnd / AudioInput.sampleRate,
  );
  if (cut.to <= cut.from || length < min) return null;
  if (cut.to - cut.from > WakeClassifierRules.verifierBMaxTemplateSamples) {
    return null;
  }
  var from = cut.from, to = cut.to;
  final missing = min - (to - from);
  if (missing > 0) {
    from -= missing ~/ 2;
    to += missing - missing ~/ 2;
    if (from < 0) {
      to -= from;
      from = 0;
    }
    if (to > length) {
      from -= to - length;
      to = length;
    }
  }
  return (from: from, to: to);
}

/// The template clip of an enrollment recording: [verifierBTemplateWindow]
/// of [pcm] (the speech from [speechStart] to [speechEnd], samples in
/// [pcm]) scaled to the peak [WakeClassifierRules.verifyPeak]. [pcm] needs
/// real audio around the speech (`Utterance.context`). `null` when the
/// recording is too short.
Int16List? verifierBTemplateClip(
  Int16List pcm,
  int speechStart,
  int speechEnd,
) {
  final w = verifierBTemplateWindow(pcm.length, speechStart, speechEnd);
  if (w == null) return null;
  return normalizePeak(
    Int16List.sublistView(pcm, w.from, w.to),
    target: WakeClassifierRules.verifyPeak,
    minPeak: 1,
  );
}

/// The enrollment side: the embedding sequence of the template cut, or
/// `null` (cut too short, fewer than 76 mel frames, or fewer than
/// [WakeClassifierRules.verifierBMinTemplateFrames] embedding frames). The
/// audio is not kept. [features] must be open.
Future<Float32List?> verifierBTemplate(
  WakeSequenceExtractor features,
  Int16List pcm,
  int speechStart,
  int speechEnd,
) async {
  final clip = verifierBTemplateClip(pcm, speechStart, speechEnd);
  if (clip == null) return null;
  final seq = await features.sequence(clip);
  if (seq == null ||
      seq.length ~/ verifierBFrameSize <
          WakeClassifierRules.verifierBMinTemplateFrames) {
    return null;
  }
  return seq;
}

/// A [WakeVerifier] that needs to know where the decision window of stage 1
/// ends inside the clip (the listener calls [confirmAt] when it can).
abstract interface class WakeEndAwareVerifier implements WakeVerifier {
  /// Like [confirm]; [endSample] is the end of the decision window in [pcm].
  Future<bool> confirmAt(Int16List pcm, int endSample);
}

/// Verdict log of [VerifierBWakeVerifier]: [verifier] is `b` or the
/// [fallbackLabel], [score] and [threshold] only for `b`.
typedef VerifierBDecision = void Function(
  String verifier,
  double? score,
  double? threshold,
);

/// Stage 2 with verifier B (WP143): with enrolled sequences B decides, else
/// (or on any error of B) the [fallback] (hw2) does. Never both for one clip.
final class VerifierBWakeVerifier implements WakeEndAwareVerifier {
  /// Creates the verifier.
  VerifierBWakeVerifier({
    required this.templates,
    required this.features,
    required this.fallback,
    Float32List? mu,
    this.fallbackLabel = 'hw2',
    this.onDecision,
    this.thresholds = const {
      WakeTemplates.wordW: WakeClassifierRules.verifierBThresholdW,
      WakeTemplates.wordHw: WakeClassifierRules.verifierBThresholdHw,
    },
  }) : mu = mu ?? wakeVerifierBMu;

  /// The enrolled templates of all speakers (empty: no B).
  final Future<List<WakeTemplates>> Function() templates;

  /// New feature chain (the plain one, no classifier needed).
  final WakeFeatureExtractor Function() features;

  /// Decides without enrolled sequences and when B fails.
  final WakeVerifier fallback;

  /// `mu` of B.
  final Float32List mu;

  /// Name of the fallback in the log.
  final String fallbackLabel;

  /// Threshold per word (`WakeTemplates.wordW`, `wordHw`).
  final Map<String, double> thresholds;

  /// Called with every verdict.
  final VerifierBDecision? onDecision;

  WakeFeatureExtractor? _extractor;
  Future<void>? _opening;
  String _kind = 'b';

  @override
  String get kind => _kind;

  @override
  Future<bool> confirm(Int16List pcm) {
    // The listener's clip ends [WakeClassifierRules.verifyTail] after the
    // decision window.
    return confirmAt(
      pcm,
      math.max(
        0,
        pcm.length - durationToSamples(WakeClassifierRules.verifyTail),
      ),
    );
  }

  @override
  Future<bool> confirmAt(Int16List pcm, int endSample) async {
    final byWord = await _sequences();
    if (byWord.isEmpty) return _viaFallback(pcm);
    ({double score, double threshold, bool ok})? verdict;
    try {
      final raw = await _sequence(verifierBLiveClip(pcm, endSample));
      final live = raw == null ? null : VerifierBSequence.prepare(raw, mu);
      verdict = _decide(live, byWord);
    } on Object {
      verdict = null;
    }
    if (verdict == null) return _viaFallback(pcm);
    _kind = 'b';
    onDecision?.call('b', verdict.score, verdict.threshold);
    return verdict.ok;
  }

  /// The word with the largest margin to its threshold decides the log;
  /// the clip passes when any word reaches its threshold. A [live] sequence
  /// that is `null` (clip too short for any window) scores -1: rejected.
  ({double score, double threshold, bool ok})? _decide(
    VerifierBSequence? live,
    Map<String, List<VerifierBSequence>> byWord,
  ) {
    double? score, threshold;
    var ok = false;
    for (final MapEntry(key: word, value: list) in byWord.entries) {
      final thr = thresholds[word];
      if (thr == null) continue;
      final s = live == null ? -1.0 : verifierBScore(live, list);
      if (threshold == null || s - thr > score! - threshold) {
        score = s;
        threshold = thr;
      }
      if (s >= thr) ok = true;
    }
    if (score == null || threshold == null) return null;
    return (score: score, threshold: threshold, ok: ok);
  }

  Future<bool> _viaFallback(Int16List pcm) async {
    onDecision?.call(fallbackLabel, null, null);
    _kind = fallback.kind;
    final ok = await fallback.confirm(pcm);
    // The fallback may pick its engine while it confirms (Parakeet or
    // Whisper): [kind] is the one that decided.
    _kind = fallback.kind;
    return ok;
  }

  /// Prepared template sequences per word; only templates of the feature
  /// version of `mu`.
  Future<Map<String, List<VerifierBSequence>>> _sequences() async {
    final out = <String, List<VerifierBSequence>>{};
    try {
      for (final t in await templates()) {
        if (t.featureVersion != wakeVerifierBFeatureVersion) continue;
        for (final s in t.sequences) {
          if (s.frames < WakeClassifierRules.verifierBMinTemplateFrames) {
            continue;
          }
          (out[s.word] ??= []).add(VerifierBSequence.prepare(s.values, mu));
        }
      }
    } on Object {
      return {};
    }
    return out;
  }

  Future<Float32List?> _sequence(Int16List clip) async {
    final extractor = _extractor ??= features();
    if (extractor is! WakeSequenceExtractor) {
      throw StateError('Merkmalskette kann keine Folge');
    }
    await (_opening ??= extractor.open());
    return extractor.sequence(clip);
  }

  /// Releases the feature models.
  Future<void> close() async {
    final e = _extractor;
    _extractor = null;
    _opening = null;
    await e?.close();
  }
}
