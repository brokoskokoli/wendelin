import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// The share text for a failed `bring__add_items` call: one line per item
/// of its arguments; `null` if [call] is no such call, the failure was not
/// one of the API (no fallback hint) or there are no items.
String? bringShareTextFor(ToolCallBlock call, ToolOutcome outcome) {
  if (call.name != 'bring__add_items' || !outcome.isError) return null;
  final text = outcome.text;
  if (!text.contains(bringFallbackHint) && !text.contains(bringRetryHint)) {
    return null;
  }
  final Object? args;
  try {
    args = jsonDecode(call.argumentsJson);
  } on FormatException {
    return null;
  }
  final raw = args is Map<String, Object?> ? args['items'] : null;
  final items = <BringItem>[
    if (raw is List<Object?>)
      for (final e in raw)
        if (e is String && e.trim().isNotEmpty)
          BringItem(name: e.trim())
        else if (e is Map<String, Object?> &&
            e['name'] is String &&
            (e['name']! as String).trim().isNotEmpty)
          BringItem(
            name: (e['name']! as String).trim(),
            spec: switch (e['spec']) {
              final String s => s.trim(),
              _ => '',
            },
          ),
  ];
  if (items.isEmpty) return null;
  return BringAppFallback.shareText(items);
}
