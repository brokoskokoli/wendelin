import 'dart:typed_data';

import '../dev/dev_archive.dart';
import '../dev/dev_clips.dart';
import '../dev/wake_shadow_run.dart';
import '../io/audio_input.dart';
import 'barge_verifier.dart';
import 'wake_verifier.dart';
import 'wake_word_engine.dart';

// WP155: notes the wake listener and the barge-in detector make in the
// developer archive. Pure bookkeeping, never part of the voice decision.

/// The transcript note of the hook; a throwing hook counts as none (the
/// archive never changes the voice decision).
Map<String, Object?> _takeStt(DevClips? clips) {
  try {
    return clips?.archive?.takeStt() ?? const {};
  } on Object {
    return const {};
  }
}

/// WP171: the values of both stage 1 recognizers in a case: highest model
/// score and template similarity/margin of the run, the limits, which one
/// decides (`primary`), which one would have triggered (`would`) and whether
/// the deciding one did (`fired`). Windows of one recognizer only leave the
/// other one's fields out.
void noteShadowFields(
  DevArchiveCase? arch,
  ShadowPeaks p,
  double above, {
  required bool fired,
}) {
  if (arch == null || p.isEmpty) return;
  arch.meta
    ..['primary'] = p.primaryModel ? 'model' : 'templates'
    ..['would'] = p.would(above)
    ..['fired'] = fired;
  if (p.modelPeak != null) {
    arch.meta
      ..['sh_model_peak'] = p.modelPeak!.toStringAsFixed(4)
      ..['thr_model'] = above.toStringAsFixed(4);
  }
  if (p.margin != null) {
    arch.meta
      ..['sh_tmpl_peak'] = p.similarity?.toStringAsFixed(4)
      ..['sh_tmpl_margin'] = p.margin!.toStringAsFixed(4)
      ..['thr_tmpl'] = p.threshold?.toStringAsFixed(4);
  }
}

/// Opens the case of a wake candidate and notes what the engine said;
/// [shadow] are the values of both recognizers around the hit.
DevArchiveCase? noteWakeCandidate(
  DevClips? clips,
  WakeWordHit hit, {
  ShadowPeaks? shadow,
  double above = 0,
}) {
  final arch = clips?.archiveCase('idle');
  arch?.meta.addAll({
    'score': hit.score?.toStringAsFixed(4),
    'conf': hit.confidence?.toStringAsFixed(4),
    'rule': hit.reason,
    'direct': hit.direct,
    'hold_ms': hit.holdMs,
  });
  if (shadow != null) noteShadowFields(arch, shadow, above, fired: true);
  return arch;
}

/// Opens the (finished) case of a run no recognizer decided: `near-miss`, or
/// `shadow-would` when the shadow recognizer reached its candidate limit.
DevArchiveCase? noteShadowCase(DevClips? clips, ShadowCase miss, double above) {
  final c = clips?.archiveCase('idle');
  if (c == null) return null;
  final p = miss.peaks;
  c.meta.addAll({
    'score': p.modelPeak?.toStringAsFixed(4),
    'run_ms': miss.ms,
    'path': p.would(above) == 'none' ? 'near-miss' : 'shadow-would',
  });
  noteShadowFields(c, p, above, fired: false);
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
  _takeStt(clips); // forget an older transcript
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
    ..addAll(_takeStt(clips));
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
    ..addAll(_takeStt(clips));
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
