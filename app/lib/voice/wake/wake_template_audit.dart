import 'package:wendelin_voice/wendelin_voice.dart';

import '../voice_log.dart';

/// Outcome of [auditTemplates].
final class TemplateAudit {
  /// Creates an outcome.
  const TemplateAudit({required this.removed, required this.left});

  /// Templates dropped as outliers.
  final int removed;

  /// Templates that remain.
  final int left;

  /// Fewer than [minimum] remain: the voice should be learned again.
  bool needsRelearn(int minimum) => left < minimum;
}

/// Checks the stored templates of [speakerId] once against each other
/// (WP140): outliers in the centered space (clicks, other words that an
/// older enrollment accepted) are removed and the rest is stored again.
/// `null` if there is nothing to check (no templates, other feature
/// version or center: they must be learned again anyway). Never throws:
/// a failing store leaves everything as it was.
Future<TemplateAudit?> auditTemplates(
  WakeTemplateStore store,
  String speakerId,
) async {
  try {
    final t = await store.load(speakerId);
    if (t == null || t.embeddings.isEmpty || t.center != wakeCenterId) {
      return null;
    }
    final r = pruneOutliers(t.embeddings, wakeCenterMean);
    if (r.removed > 0) {
      await store.save(
        WakeTemplates(
          speakerId: t.speakerId,
          featureVersion: t.featureVersion,
          threshold: t.threshold,
          embeddings: List.unmodifiable(r.kept),
          center: t.center,
        ),
      );
    }
    voiceLog('wake-audit', {'removed': r.removed, 'left': r.kept.length});
    return TemplateAudit(removed: r.removed, left: r.kept.length);
  } on Object catch (e) {
    voiceLog('wake-audit', {'error': errorCode(e)});
    return null;
  }
}

/// Fingerprint of a template set (FNV-1a over count and embedding bytes):
/// changes with every new enrollment, removal or other edit of the set.
String templateFingerprint(WakeTemplates t) {
  var h = 0xcbf29ce484222325;
  void mix(int b) {
    h = ((h ^ (b & 0xff)) * 0x100000001b3) & 0x7fffffffffffffff;
  }

  mix(t.embeddings.length);
  for (final e in t.embeddings) {
    final bytes = e.buffer.asUint8List(e.offsetInBytes, e.lengthInBytes);
    for (final b in bytes) {
      mix(b);
    }
  }
  return h.toRadixString(16);
}

/// [auditTemplates] only once per template set (WP140): the audit is
/// relative, so a repeat could shave off a small real group step by step.
/// [readMark]/[writeMark] keep the fingerprint of the audited set; a new
/// or changed set (new enrollment) is audited once more. `null` if the set
/// was already audited or there is nothing to check.
Future<TemplateAudit?> auditTemplatesOnce(
  WakeTemplateStore store,
  String speakerId, {
  required Future<String?> Function() readMark,
  required Future<void> Function(String mark) writeMark,
}) async {
  try {
    final before = await store.load(speakerId);
    if (before == null) return null;
    if (await readMark() == templateFingerprint(before)) return null;
    final r = await auditTemplates(store, speakerId);
    if (r == null) return null;
    final after = r.removed > 0 ? await store.load(speakerId) : before;
    if (after != null) await writeMark(templateFingerprint(after));
    return r;
  } on Object catch (e) {
    voiceLog('wake-audit', {'error': errorCode(e)});
    return null;
  }
}
