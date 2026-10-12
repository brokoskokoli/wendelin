import 'dart:convert';

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
