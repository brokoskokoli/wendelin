import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart'
    show redactSecretValues, redactSecrets, redactedValue;

import 'voice_log.dart';

/// Prefix of the developer log in the log (`adb logcat | grep Wendelin/dev`,
/// WP148). Content that [voiceLog] never writes (transcripts, tool
/// arguments and results) appears only here and only in developer mode.
const devLogPrefix = 'Wendelin/dev:';

/// Longest value of a [devLog] field in characters; longer text is cut.
const devLogMaxChars = 300;

/// Whether the developer mode is on (setting `debug.developerMode`). Set
/// at engine start (`runWendelinApp`), by the switch in the app language
/// settings and re-read from the database at each voice session and request
/// (`refreshDevLogFlag`), so the switch works in every engine with storage
/// (app, overlay, station) without a restart. The recognizer and wake
/// engines have no database and stay off. Without it [devLog] writes
/// nothing.
bool devLogEnabled = false;

/// Where the lines go (tests capture them).
@visibleForTesting
void Function(String line) devLogSink = _print;

void _print(String line) => debugPrint(line);

/// Logs [event] with [fields], including content, **only** in developer mode.
///
/// Strings are shortened to [devLogMaxChars] (line breaks become spaces).
/// Secrets never appear: values of keys such as `token`, `key`, `password`,
/// `authorization` are replaced (nested JSON too), `Bearer …` and `sk-…`
/// are masked, and the places that [detectSensitiveContent] flags (card
/// number, IBAN, password or PIN with its value, API key) are replaced by
/// `***` ([redactSensitiveContent]); the rest of the text stays readable.
void devLog(String event, [Map<String, Object?> fields = const {}]) {
  if (!devLogEnabled) return;
  final safe = redactSecrets(fields) as Map<String, Object?>;
  final b = StringBuffer('$devLogPrefix $event engine=$voiceLogEngine');
  for (final MapEntry(:key, :value) in safe.entries) {
    if (value == null) continue;
    b.write(' $key=${_format(value)}');
  }
  devLogSink(b.toString());
}

/// The JSON text [json] (tool arguments) for [devLog]: parsed so that keys
/// like `password` are redacted, [json] itself if it is no JSON.
String devJson(String json) {
  try {
    return jsonEncode(redactSecrets(jsonDecode(json)));
  } on FormatException {
    return json;
  }
}

String _format(Object value) {
  if (value is num || value is bool) return '$value';
  if (value is Duration) return '${value.inMilliseconds}';
  if (value is Enum) return value.name;
  return jsonEncode(_text('$value'));
}

String _text(String raw) {
  final clean = redactSecretValues(raw).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean == redactedValue) return redactedValue;
  final safe = redactSensitiveContent(clean, mask: redactedValue);
  return safe.length <= devLogMaxChars
      ? safe
      : '${safe.substring(0, devLogMaxChars)}…(${safe.length})';
}
