import 'package:flutter/foundation.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Prefix of the voice diagnostics in the log (`adb logcat | grep
/// Wendelin/voice`). The Kotlin side logs under the same tag.
const voiceLogPrefix = 'Wendelin/voice:';

/// Which Flutter engine of the process logs: `app` (main screen),
/// `overlay` (assistant) or `recognizer` (system speech recognizer). Set
/// once by the entry point; every engine runs in its own isolate group.
String voiceLogEngine = 'app';

/// Where the lines go (tests capture them). Release builds print too, like
/// the „Whisper-Zeit“ lines, so the maintainer can read them on a phone.
@visibleForTesting
void Function(String line) voiceLogSink = _print;

void _print(String line) => debugPrint(line);

/// Field values that may be logged: codes and identifiers, never content.
final _code = RegExp(r'^[a-z0-9][a-z0-9_.:()|-]{0,47}$');

/// Logs the voice event [event] with [fields] (no content, WP30).
///
/// Only numbers, booleans, durations (as ms), enums (their name) and short
/// lower-case codes (`whisper-small`, `no-speech`) are written; any other
/// value – a transcript, a note name, an error message – becomes `?`.
/// Errors are logged by their type ([errorCode]).
void voiceLog(String event, [Map<String, Object?> fields = const {}]) {
  final b = StringBuffer('$voiceLogPrefix $event engine=$voiceLogEngine');
  for (final MapEntry(:key, :value) in fields.entries) {
    if (value == null) continue;
    b.write(' $key=${logValue(value)}');
  }
  voiceLogSink(b.toString());
}

/// [value] as it appears in a [voiceLog] line.
@visibleForTesting
String logValue(Object value) => switch (value) {
  final int v => '$v',
  final double v => v.toStringAsFixed(2),
  final bool v => '$v',
  final Duration v => '${v.inMilliseconds}',
  final Enum v => v.name,
  final String v when _code.hasMatch(v) => v,
  _ => '?',
};

/// Log code of [error]: its type in lower case (`timeoutexception`), never
/// its message (it may quote content).
String errorCode(Object error) {
  final type = error.runtimeType.toString().toLowerCase();
  final code = type.replaceAll(RegExp('[^a-z0-9_]'), '');
  return code.isEmpty ? 'error' : code;
}

/// Diagnostics of the conversation events (no contents): `barge-in kind=…`
/// and `conv-exit reason=…`; other pipeline events are not logged here.
void voiceLogPipelineEvent(VoiceEvent e) {
  switch (e) {
    case VoiceBargeIn(:final signal):
      voiceLog('barge-in', {'kind': signal.code});
    case VoiceConversationEnded(:final reason):
      voiceLog('conv-exit', {'reason': reason});
    default:
      break;
  }
}
