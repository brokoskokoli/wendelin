import 'dart:typed_data';

import '../dev/dev_archive.dart';
import '../dev/dev_clips.dart';
import '../io/audio_input.dart';
import 'barge_verifier.dart';
import 'wake_verifier.dart';
import 'wake_word_engine.dart';

// WP155: notes the wake listener and the barge-in detector make in the
// developer archive. Pure bookkeeping, never part of the voice decision.

/// Opens the case of a wake candidate and notes what the engine said.
DevArchiveCase? noteWakeCandidate(DevClips? clips, WakeWordHit hit) {
  final arch = clips?.archiveCase('idle');
  arch?.meta.addAll({
    'score': hit.score?.toStringAsFixed(4),
    'conf': hit.confidence?.toStringAsFixed(4),
    'rule': hit.reason,
    'direct': hit.direct,
    'hold_ms': hit.holdMs,
  });
  return arch;
}

/// Opens the (finished) case of a near miss.
DevArchiveCase? noteNearMiss(DevClips? clips, NearMiss miss) {
  final c = clips?.archiveCase('idle');
  if (c == null) return null;
  c.meta.addAll({
    'score': miss.peak.toStringAsFixed(4),
    'run_ms': miss.ms,
    'path': 'near-miss',
  });
  c.finish('near-miss');
  return c;
}

/// Hands the clip the verifier is about to hear to the case.
void noteVerifyClip(
  DevClips? clips,
  DevArchiveCase? arch,
  String event,
  Int16List pcm,
  String markName,
  int markSamples,
) {
  arch?.verifyClip(
    DevClip(
      event: event,
      pcm: Int16List.fromList(pcm),
      at: DateTime.now(),
      marksMs: {markName: samplesToDuration(markSamples).inMilliseconds},
    ),
  );
  clips?.archive?.takeStt(); // forget an older transcript
}

/// Notes the wake verifier's answer.
void noteWakeVerdict(
  DevClips? clips,
  DevArchiveCase? arch,
  WakeVerifier v,
  String verdict,
) {
  if (arch == null) return;
  arch.meta
    ..['verifier'] = v.kind
    ..['verdict'] = verdict
    ..addAll(v is VerdictDetail ? (v as VerdictDetail).lastDetail : {})
    ..addAll(clips?.archive?.takeStt() ?? {});
}

/// Closes the case of a wake candidate after the check.
void finishWakeCase(DevArchiveCase? arch, String verdict, bool ok) {
  arch
    ?..meta['path'] = verdict
    ..finish(ok ? 'accepted' : 'rejected');
}

/// Opens the case of a barge-in candidate.
DevArchiveCase? noteBargeCandidate(DevClips? clips, double? sim, {bool? busy}) {
  final c = clips?.archiveCase('barge');
  c?.meta.addAll({'sim': sim?.toStringAsFixed(4), 'busy': ?busy});
  return c;
}

/// Notes the barge-in check's answer.
void noteBargeVerdict(
  DevClips? clips,
  DevArchiveCase? arch,
  BargeVerdict verdict,
) {
  if (arch == null) return;
  arch.meta
    ..['result'] = verdict.result
    ..['reason'] = verdict.reason
    ..['verifier'] = verdict.verifier
    ..['score'] = verdict.score?.toStringAsFixed(4)
    ..addAll(clips?.archive?.takeStt() ?? {});
}

/// Closes the case of a barge-in candidate after the check.
void finishBargeCase(DevArchiveCase? arch, BargeVerdict verdict) {
  if (arch == null) return;
  if (verdict.keyword != null) {
    arch.finish('accepted');
  } else if (verdict.result == 'skip') {
    // The check did not run through (time out, error): no judgment.
    arch.finish('dropped', {'reason': verdict.reason ?? 'skip'});
  } else {
    arch.finish('rejected');
  }
}
