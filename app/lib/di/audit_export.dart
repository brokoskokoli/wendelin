import 'dart:convert';

/// Payload keys that can hold content (what was said or written, tool
/// arguments, free texts). They stay in the local audit log but never leave
/// the device through the export (WP71).
const auditContentKeys = {'text', 'arguments', 'description'};

/// The audit export [json] (as written by the repository) without contents:
/// recognized speech, request texts, tool arguments and confirmation
/// descriptions are dropped from every entry, including old entries that
/// were stored with them. Ids, times, kinds and results stay.
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
                if (!auditContentKeys.contains(e.key)) e.key: e.value,
            },
        }
      else
        r,
  ]);
}
