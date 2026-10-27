import 'dart:math' as math;
import 'dart:typed_data';

import 'speaker_embedder.dart';
import 'speaker_match.dart';
import 'speaker_profile.dart';
import 'speaker_profile_store.dart';

/// Why [SpeakerIdentifier.enroll] refused.
enum SpeakerEnrollProblem {
  /// Fewer than [SpeakerIdentifier.minEnrollSamples] sentences.
  tooFewSamples,

  /// A recording is shorter than [SpeakerIdentifier.minEnrollAudioSamples].
  tooShort,

  /// The sentences do not sound like one person (someone else spoke, or
  /// loud noise); nothing is stored.
  inconsistent,

  /// The embedder failed.
  failed,
}

/// Enrollment refused.
final class SpeakerEnrollException implements Exception {
  /// Creates the exception.
  const SpeakerEnrollException(this.problem);

  /// Reason.
  final SpeakerEnrollProblem problem;

  @override
  String toString() => 'SpeakerEnrollException(${problem.name})';
}

/// Outcome of an enrollment: what the calibration found.
final class SpeakerEnrollResult {
  /// Creates the result.
  const SpeakerEnrollResult({
    required this.profile,
    required this.meanScore,
    required this.minScore,
    required this.thresholdClamped,
  });

  /// The stored profile.
  final SpeakerProfile profile;

  /// Mean leave-one-out score of the sentences (how steady the voice is).
  final double meanScore;

  /// Lowest leave-one-out score.
  final double minScore;

  /// Whether the threshold hit the conservative floor or the ceiling.
  final bool thresholdClamped;
}

/// Speaker recognition on top of a [SpeakerEmbedder] and a
/// [SpeakerProfileStore] (WP92a): enrollment per person from several
/// sentences, cosine against the mean embedding, a threshold calibrated
/// from the enrollment scores but never below [thresholdFloor], and
/// „unknown“ whenever in doubt (lieber unbekannt als falsch erkannt).
final class SpeakerIdentifier implements SpeakerRecognizer {
  /// Creates the identifier.
  SpeakerIdentifier({
    required this.embedder,
    required this.store,
    this.diagnostics,
  });

  /// Receives one line per enrollment (`speaker-enroll …`, never a name).
  final void Function(String line)? diagnostics;

  /// Embedding model.
  final SpeakerEmbedder embedder;

  /// Encrypted profiles.
  final SpeakerProfileStore store;

  /// Fewest sentences for an enrollment (5 are recommended).
  static const minEnrollSamples = 3;

  /// Recommended number of sentences.
  static const recommendedEnrollSamples = 5;

  /// Shortest audio that is embedded when recognizing (1 s).
  static const minIdentifySamples = speakerSampleRate;

  /// Shortest enrollment sentence (1.5 s).
  static const minEnrollAudioSamples = speakerSampleRate * 3 ~/ 2;

  /// Lowest threshold ever used. The model card names 0.33 as the
  /// equal-error point; stricter, so a stranger's voice stays „unknown“.
  static const thresholdFloor = 0.45;

  /// Highest threshold (natural speech varies more than the enrollment).
  static const thresholdCeiling = 0.60;

  /// How far the best person must lead the second one.
  static const ambiguityMargin = 0.06;

  /// Spread of the enrollment scores kept below the threshold.
  static const spreadFactor = 2.0;

  /// The enrolled persons, read from the store every time (no cache), so
  /// another identifier on the same store (overlay engine) sees deletions.
  Future<List<SpeakerProfile>> profiles() => store.load();

  /// Whether anyone is enrolled.
  Future<bool> get hasProfiles async => (await profiles()).isNotEmpty;

  /// Enrolls [name] from the recordings [samples] (mono 16 kHz, one per
  /// sentence); replaces the profile [id]. Only embeddings are stored.
  Future<SpeakerEnrollResult> enroll({
    required String id,
    required String name,
    required List<Int16List> samples,
    DateTime? now,
  }) async {
    if (samples.length < minEnrollSamples) {
      throw const SpeakerEnrollException(SpeakerEnrollProblem.tooFewSamples);
    }
    if (samples.any((s) => s.length < minEnrollAudioSamples)) {
      throw const SpeakerEnrollException(SpeakerEnrollProblem.tooShort);
    }
    final embeddings = <Float32List>[];
    try {
      for (final s in samples) {
        embeddings.add(normalized(await embedder.embed(s)));
      }
    } on Object {
      throw const SpeakerEnrollException(SpeakerEnrollProblem.failed);
    }
    final dim = embeddings.first.length;
    if (dim == 0 || embeddings.any((e) => e.length != dim)) {
      throw const SpeakerEnrollException(SpeakerEnrollProblem.failed);
    }
    final scores = looScores(embeddings);
    final mean = scores.reduce((a, b) => a + b) / scores.length;
    final low = scores.reduce(math.min);
    if (low < thresholdFloor) {
      throw const SpeakerEnrollException(SpeakerEnrollProblem.inconsistent);
    }
    final raw = calibrateThreshold(scores);
    final threshold = raw.clamp(thresholdFloor, thresholdCeiling);
    final profile = SpeakerProfile(
      id: id,
      name: name,
      embeddings: embeddings,
      threshold: threshold,
      createdAt: now ?? DateTime.now(),
    );
    await store.save(profile);
    diagnostics?.call(
      'speaker-enroll samples=${samples.length} '
      'thr=${threshold.toStringAsFixed(2)} '
      'clamped=${raw != threshold} '
      'scores=${low.toStringAsFixed(2)}/'
      '${scores.reduce(math.max).toStringAsFixed(2)}',
    );
    return SpeakerEnrollResult(
      profile: profile,
      meanScore: mean,
      minScore: low,
      thresholdClamped: raw != threshold,
    );
  }

  /// Mean minus [spreadFactor] standard deviations of the enrollment
  /// [scores]; the caller clamps it.
  static double calibrateThreshold(List<double> scores) {
    final mean = scores.reduce((a, b) => a + b) / scores.length;
    var v = 0.0;
    for (final s in scores) {
      v += (s - mean) * (s - mean);
    }
    return mean - spreadFactor * math.sqrt(v / scores.length);
  }

  /// Each embedding against the mean of the others (leave one out).
  static List<double> looScores(List<Float32List> embeddings) => [
    for (var i = 0; i < embeddings.length; i++)
      cosine(
        meanOf([
          for (var j = 0; j < embeddings.length; j++)
            if (j != i) embeddings[j],
        ]),
        embeddings[i],
      ),
  ];

  /// Who spoke [pcm]; any failure is „unknown“, never an exception.
  @override
  Future<SpeakerMatch> identify(Int16List pcm) async {
    var count = 0;
    try {
      final all = await profiles();
      count = all.length;
      if (all.isEmpty) {
        return const SpeakerMatch.unknown(
          SpeakerUnknownReason.noProfiles,
          profileCount: 0,
        );
      }
      if (pcm.length < minIdentifySamples) {
        return SpeakerMatch.unknown(
          SpeakerUnknownReason.tooShort,
          profileCount: count,
        );
      }
      final e = normalized(await embedder.embed(pcm));
      return decide(e, all);
    } on Object catch (error) {
      return SpeakerMatch.unknown(
        SpeakerUnknownReason.failed,
        profileCount: count,
        failure: error.runtimeType.toString().toLowerCase(),
      );
    }
  }

  /// The decision for an embedding [e] against [profiles] (pure).
  static SpeakerMatch decide(Float32List e, List<SpeakerProfile> profiles) {
    SpeakerProfile? best;
    var bestScore = -2.0;
    var second = -2.0;
    for (final p in profiles) {
      if (p.centroid.length != e.length) continue;
      final s = cosine(p.centroid, e);
      if (s > bestScore) {
        second = bestScore;
        bestScore = s;
        best = p;
      } else if (s > second) {
        second = s;
      }
    }
    if (best == null) {
      return SpeakerMatch.unknown(
        SpeakerUnknownReason.failed,
        profileCount: profiles.length,
        failure: 'dimension',
      );
    }
    final threshold = math.max(best.threshold, thresholdFloor);
    final secondScore = second > -2.0 ? second : null;
    if (bestScore < threshold) {
      return SpeakerMatch.unknown(
        SpeakerUnknownReason.belowThreshold,
        score: bestScore,
        threshold: threshold,
        second: secondScore,
        profileCount: profiles.length,
      );
    }
    if (bestScore - second < ambiguityMargin) {
      return SpeakerMatch.unknown(
        SpeakerUnknownReason.ambiguous,
        score: bestScore,
        threshold: threshold,
        second: secondScore,
        profileCount: profiles.length,
      );
    }
    return SpeakerMatch.known(
      personId: best.id,
      name: best.name,
      score: bestScore,
      threshold: threshold,
      second: secondScore,
      profileCount: profiles.length,
    );
  }

  /// Deletes the person [id] with all embeddings.
  Future<void> remove(String id) async {
    await store.delete(id);
  }

  /// Deletes every profile.
  Future<void> removeAll() async {
    await store.clear();
  }

  /// Frees the embedding model.
  Future<void> release() => embedder.release();
}
