import 'dart:convert';

/// Payload keys the export keeps, per entry kind (positive list, WP71).
/// Only ids, codes, numbers and flags; free texts (what was said or written,
/// tool arguments, descriptions, messages, details) never leave the device,
/// and a key that is not listed here is dropped, also in old entries.
const auditExportKeys = <String, Set<String>>{
  'request': {
    'source',
    'trigger',
    'language',
    'sttConfidence',
    'requestEscalation',
    'whileLocked',
    'refused',
  },
  'routing': {'profileId', 'modelId'},
  'toolCall': {
    'callId',
    'tool',
    'decision',
    'status',
    'durationMs',
    'undo',
    'trigger',
    'whileLocked',
  },
  'confirmation': {
    'type',
    'callId',
    'tool',
    'fromProfile',
    'toProfile',
    'reason',
    'approved',
  },
  'escalation': {'fromProfile', 'toProfile', 'reason'},
  'usage': {
    'profileId',
    'modelId',
    'inputTokens',
    'outputTokens',
    'cacheReadTokens',
    'cacheWriteTokens',
    'costMicros',
    'budgetWarning',
    'spentMicros',
    'budgetMicros',
  },
  'verification': {
    'source',
    'profileId',
    'status',
    'latencyMs',
    'spokenCheck',
    'accepted',
    'reason',
  },
  'error': {'source', 'error'},
};

/// The audit export [json] (as written by the repository) reduced to the
/// keys of [auditExportKeys]. Entries of an unknown kind keep no payload.
String auditExportWithoutContent(String json) {
  final rows = jsonDecode(json) as List<Object?>;
  return const JsonEncoder.withIndent('  ').convert([
    for (final r in rows)
      if (r is Map<String, Object?>)
        {
          ...r,
          if (r['payload'] case final Map<String, Object?> p)
            'payload': {
              for (final e in p.entries)
                if (auditExportKeys[r['kind']]?.contains(e.key) ?? false)
                  e.key: e.value,
            },
        }
      else
        r,
  ]);
}
