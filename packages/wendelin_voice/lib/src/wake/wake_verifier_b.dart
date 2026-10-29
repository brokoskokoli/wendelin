import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../io/audio_input.dart';
import '../models/wake_classifier_catalog.dart';
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
  return verifierBScaleToPeak(out);
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
  return verifierBScaleToPeak(Int16List.sublistView(pcm, w.from, w.to));
}

/// Scales [pcm] to the peak [WakeClassifierRules.verifyPeak] like the
/// measurement (Python: `trunc(x * peak / max * 32767)`): truncating, not
/// rounding, so that the embeddings match. [pcm] without any signal stays.
Int16List verifierBScaleToPeak(Int16List pcm) {
  var peak = 0;
  for (final s in pcm) {
    final a = s < 0 ? -s : s;
    if (a > peak) peak = a;
  }
  if (peak < 1) return pcm;
  final gain = WakeClassifierRules.verifyPeak * 32767 / peak;
  final out = Int16List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    out[i] = (pcm[i] * gain).truncate().clamp(-32768, 32767);
  }
  return out;
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

/// Scores a clip against the enrolled HW sequences (shared by the idle
/// [VerifierBWakeVerifier] and the barge-in check, WP151).
final class VerifierBScorer {
  /// Creates the scorer.
  VerifierBScorer({
    required this.templates,
    required this.features,
    Float32List? mu,
    this.threshold = WakeClassifierRules.verifierBThresholdHw,
  }) : mu = mu ?? wakeVerifierBMu;

  /// The enrolled templates of all speakers (empty: no B).
  final Future<List<WakeTemplates>> Function() templates;

  /// New feature chain (the plain one, no classifier needed).
  final WakeFeatureExtractor Function() features;

  /// `mu` of B.
  final Float32List mu;

  /// Threshold of the HW head, valid whichever word was heard.
  final double threshold;

  WakeFeatureExtractor? _extractor;
  Future<void>? _opening;
  bool _closed = false;

  /// Score of the decision window ending at [endSample] of [pcm]: `null`
  /// when B cannot decide (no usable sequences, or an error), `-1` when the
  /// clip is too short for any window (rejected).
  Future<double?> score(Int16List pcm, int endSample) async {
    if (_closed) return null;
    final tpl = await _sequences();
    if (tpl.isEmpty) return null;
    try {
      final raw = await _sequence(verifierBLiveClip(pcm, endSample));
      final live = raw == null ? null : VerifierBSequence.prepare(raw, mu);
      return live == null ? -1.0 : verifierBScore(live, tpl);
    } on Object {
      return null;
    }
  }

  /// Prepared HW template sequences; only templates of the feature version
  /// of `mu`. Sequences of other words (`w`, stored before) are ignored.
  Future<List<VerifierBSequence>> _sequences() async {
    final out = <VerifierBSequence>[];
    try {
      for (final t in await templates()) {
        if (t.featureVersion != wakeVerifierBFeatureVersion) continue;
        for (final s in t.sequences) {
          if (s.word != WakeTemplates.wordHw) continue;
          if (s.frames < WakeClassifierRules.verifierBMinTemplateFrames) {
            continue;
          }
          out.add(VerifierBSequence.prepare(s.values, mu));
        }
      }
    } on Object {
      return [];
    }
    return out;
  }

  Future<Float32List?> _sequence(Int16List clip) async {
    // Closed while waiting for the templates: open nothing that never closes.
    if (_closed) throw StateError('Prüfer B geschlossen');
    final extractor = _extractor ??= features();
    if (extractor is! WakeSequenceExtractor) {
      throw StateError('Merkmalskette kann keine Folge');
    }
    await (_opening ??= extractor.open());
    return extractor.sequence(clip);
  }

  /// Releases the feature models.
  Future<void> close() async {
    _closed = true;
    final e = _extractor;
    _extractor = null;
    _opening = null;
    await e?.close();
  }
}

/// Stage 2 with verifier B (WP143, WP177): with enrolled sequences B decides;
/// if B does not confirm (or without sequences / on error), the optional
/// [fallback] (e.g. speech recognizer) decides if provided. Never calls the
/// fallback when B confirms.
final class VerifierBWakeVerifier
    implements WakeEndAwareVerifier, VerdictDetail {
  /// Creates the verifier.
  VerifierBWakeVerifier({
    required Future<List<WakeTemplates>> Function() templates,
    required WakeFeatureExtractor Function() features,
    this.fallback,
    Float32List? mu,
    this.fallbackLabel = 'hw2',
    this.onDecision,
    this.threshold = WakeClassifierRules.verifierBThresholdHw,
  }) : scorer = VerifierBScorer(
         templates: templates,
         features: features,
         mu: mu,
         threshold: threshold,
       );

  /// Decides without enrolled sequences, when B fails, or when B does not confirm
  /// and fallback is active. `null` when only verifier B is active.
  final WakeVerifier? fallback;

  /// Name of the fallback in the log.
  final String fallbackLabel;

  /// Threshold of the HW head, valid whichever word was heard.
  final double threshold;

  /// Called with every verdict.
  final VerifierBDecision? onDecision;

  /// The scoring of B.
  final VerifierBScorer scorer;

  String _kind = 'b';
  Map<String, Object?> _detail = const {};

  @override
  String get kind => _kind;

  @override
  Map<String, Object?> get lastDetail => _detail;

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
    _detail = const {};
    final s = await scorer.score(pcm, endSample);
    if (s == null) {
      if (fallback != null) return _viaFallback(pcm);
      _kind = 'b';
      _detail = {'score': null, 'thr': threshold};
      onDecision?.call('b', null, threshold);
      return false;
    }
    _kind = 'b';
    _detail = {'score': s, 'thr': threshold};
    onDecision?.call('b', s, threshold);
    if (s >= threshold) return true;
    if (fallback != null) return _viaFallback(pcm);
    return false;
  }

  Future<bool> _viaFallback(Int16List pcm) async {
    final fb = fallback;
    if (fb == null) return false;
    onDecision?.call(fallbackLabel, null, null);
    _kind = fb.kind;
    final ok = await fb.confirm(pcm);
    // The fallback may pick its engine while it confirms (Parakeet or
    // Whisper): [kind] is the one that decided.
    _kind = fb.kind;
    return ok;
  }

  /// Releases the feature models.
  Future<void> close() => scorer.close();
}
