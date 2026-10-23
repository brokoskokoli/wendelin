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
