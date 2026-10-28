import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'dev_log.dart';
import 'voice_log.dart';

/// Developer log of one agent run (WP148): which tool ran with which
/// arguments and result, what the model answered, and on failure one line
/// with all rounds. Everything goes through [devLog], so nothing is written
/// without developer mode.
final class DevAgentTrace {
  final _text = StringBuffer();
  final _rounds = <String>[];

  /// A new request starts: forgets the rounds of the last one.
  void begin() {
    _text.clear();
    _rounds.clear();
  }

  /// The events of one request from [run], logged. Only listens along:
  /// the stream's timing and content stay as they are (no await, no extra
  /// async gap). The stored flag is re-read in the background ([refresh],
  /// fire and forget), so the switch works without a restart. Typed and
  /// spoken requests both pass here once, so no line appears twice.
  Stream<AgentEvent> observe(
    void Function() refresh,
    Stream<AgentEvent> Function() run,
  ) {
    refresh();
    begin();
    return run().map((e) {
      event(e);
      return e;
    });
  }

  /// An agent event of the running request.
  void event(AgentEvent e) {
    // Normal log (no content): reason, tool name and count only.
    if (e is AgentFailed) {
      voiceLog('agent-failed', {
        'kind': e.error,
        'tool': e.tool,
        'repeats': e.repeats,
      });
    }
    if (!devLogEnabled) return;
    switch (e) {
      case AgentTextDelta(:final text):
        _text.write(text);
      case AgentTextComplete():
        _flushText();
      case ToolCallStarted(:final call):
        _flushText();
        final n = _rounds.length + 1;
        final args = devJson(call.argumentsJson);
        _rounds.add('$n ${call.name} $args');
        devLog('tool-call', {'n': n, 'tool': call.name, 'args': args});
      case ToolCallFinished(:final call, :final outcome, :final duration):
        final n = _rounds.length;
        final result = _logResult(call.name, outcome);
        final status = outcome.isError ? 'error' : 'ok';
        if (n > 0) _rounds[n - 1] = '${_rounds[n - 1]} -> $status $result';
        devLog('tool-result', {
          'n': n,
          'tool': call.name,
          'status': status,
          'ms': duration,
          'result': result,
        });
      case AgentDone():
        _flushText();
      case AgentFailed(
        :final error,
        :final message,
        :final tool,
        :final detail,
        :final repeats,
      ):
        _flushText();
        devLog('agent-failed', {
          'kind': error,
          'message': message,
          'tool': tool,
          'repeats': repeats,
          'error': detail,
          'rounds': _rounds.length,
        });
        for (var i = 0; i < _rounds.length; i++) {
          devLog('agent-round', {'round': _rounds[i]});
        }
      default:
        break;
    }
  }

  void _flushText() {
    final text = _text.toString().trim();
    _text.clear();
    if (text.isNotEmpty) devLog('model-text', {'text': text});
  }

  /// The result as logged. Address book content (names, numbers, mail
  /// addresses, postal addresses, birthdays, organizations) never reaches the
  /// log, not even in developer mode: `contacts__find` is reduced to its
  /// structure (count, `choice_needed`). Errors carry no contact data.
  static String _logResult(String tool, ToolOutcome o) {
    final text = _resultText(o);
    if (tool != 'contacts__find' || o.isError) return text;
    try {
      final json = jsonDecode(text);
      if (json is Map && json['matches'] is List) {
        return 'contacts masked: matches=${(json['matches'] as List).length} '
            'choice_needed=${json['choice_needed']}';
      }
    } on FormatException {
      // Falls through to the full mask.
    }
    return 'contacts masked';
  }

  static String _resultText(ToolOutcome o) =>
      o.content.whereType<TextBlock>().map((b) => b.text).join(' ');
}

/// The developer log of the current request of this engine.
final devAgentTraceProvider = Provider<DevAgentTrace>((ref) => DevAgentTrace());
