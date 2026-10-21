import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Tool context at [now] in [timeZone].
ToolContext ctxAt(
  DateTime now, {
  String timeZone = 'Europe/Berlin',
  CancelToken? cancel,
}) => ToolContext(
  sessionId: 's1',
  clock: FixedClock(now),
  locale: 'de-DE',
  timeZone: timeZone,
  cancel: cancel,
);

/// Default context: Tue 2026-10-13 12:00 UTC, Europe/Berlin.
ToolContext ctx() => ctxAt(DateTime.utc(2026, 10, 13, 12));

/// The JSON object in a tool outcome's text.
Map<String, Object?> json(ToolOutcome o) =>
    jsonDecode(o.text) as Map<String, Object?>;

/// Checks the fixed confirmation of a successful [o] of [tool] (WP122): the
/// tool declares the key, and all languages can render it. [de] is the exact
/// German sentence, if given.
void expectFixed(ToolOutcome o, Tool tool, String key, {String? de}) {
  expect(o.isError, isFalse, reason: o.text);
  expect(tool, isA<FixedConfirmationTool>());
  final sentence = o.fixed;
  expect(sentence, isNotNull, reason: 'no fixed sentence: ${o.text}');
  expect(sentence!.key, key);
  expect((tool as FixedConfirmationTool).confirmationKeys, contains(key));
  for (final tag in ['de', 'en', 'fr']) {
    expect(
      renderConfirmation(sentence, tag),
      isNotNull,
      reason: '$key not renderable in $tag',
    );
  }
  if (de != null) expect(renderConfirmation(sentence, 'de'), de);
}
