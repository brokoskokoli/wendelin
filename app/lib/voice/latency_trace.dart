import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'voice_log.dart';

/// Time line of one voice request for the `latency` log line (WP120).
///
/// All times are milliseconds since the end of the speech (the endpointer
/// closed the recording, the pipeline turned to `transcribing`), taken from
/// a monotonic clock. Only numbers are logged, never text:
///
/// - `stt`: transcription ready.
/// - `calls`, `tools`: number of model calls and tool calls.
/// - `m<i>_req` / `m<i>_first` / `m<i>_done` (at most 4 calls): request of
///   the model call handed over (after the transcript or after the last tool
///   result), first token (text, thinking or tool call), call finished
///   (usage reported).
/// - `tts1`: first sentence handed to the speech output.
/// - `syn_end`: first synthesis ready (offline voice only).
/// - `audio_first` / `audio_last`: first sound / end of the last sound
///   (offline voice only).
/// - `sentences`, `s<i>_syn` (synthesis time of sentence i), `s<i>_gap`
///   (silence between the end of sentence i-1 and the start of sentence i),
///   at most 8 sentences.
///
/// `tool/latency_report.dart` turns these lines into p50/p90 per section.
final class LatencyTrace {
  /// Creates a trace; [now] is the monotonic time source, [log] the sink.
  LatencyTrace({
    Duration Function()? now,
    void Function(String event, Map<String, Object?> fields)? log,
  }) : _now = now ?? _stopwatchNow,
       _log = log ?? voiceLog;

  static final Stopwatch _watch = Stopwatch()..start();
  static Duration _stopwatchNow() => _watch.elapsed;

  /// Most model calls and sentences with their own fields.
  static const maxCalls = 4;

  /// Most sentences with their own fields.
  static const maxSentences = 8;

  final Duration Function() _now;
  final void Function(String event, Map<String, Object?> fields) _log;

  Duration? _t0;
  int _epoch = 0;
  Duration? _stt;
  Duration? _pendingReq;
  final _calls = <_Call>[];
  int _tools = 0;
  Duration? _tts1;
  Duration? _synEnd;
  final _syn = <Duration>[];
  final _starts = <Duration>[];
  final _ends = <Duration>[];
  int _sentences = 0;

  /// Whether a request is being timed.
  bool get active => _t0 != null;

  Duration _at() => _now() - _t0!;

  /// The speech ended: starts a new time line (an unfinished one is
  /// dropped).
  void begin() {
    abort();
    _t0 = _now();
  }

  /// The transcript is ready.
  void sttDone() {
    if (!active || _stt != null) return;
    _stt = _pendingReq = _at();
  }

  /// An agent event of the request.
  void agentEvent(AgentEvent e) {
    if (!active || _stt == null) return;
    switch (e) {
      case AgentTextDelta() || AgentThinkingDelta():
        _current()?.first ??= _at();
      case UsageReported():
        // A call that only answers with a tool call reports its usage
        // before the tool event: the first token never comes after done.
        final call = _current();
        final t = _at();
        call?.first ??= t;
        call?.done = t;
      case ToolCallStarted():
        _tools++;
        if (_calls.isNotEmpty) _calls.last.first ??= _at();
      case ToolCallFinished():
        _pendingReq = _at();
      default:
        break;
    }
  }

  // The call that gets the progress event: the running one, or a new one
  // (its request left after the transcript or the last tool result).
  _Call? _current() {
    if (_calls.isEmpty || _calls.last.done != null) {
      _calls.add(_Call(_pendingReq ?? _at()));
    }
    return _calls.last;
  }

  /// A sentence was handed to the speech output.
  void sentenceToTts() {
    if (!active) return;
    _tts1 ??= _at();
    _sentences++;
  }

  /// The synthesis of the next sentence took [compute].
  void synthesized(Duration compute) {
    if (!active) return;
    _synEnd ??= _at();
    _syn.add(compute);
  }

  /// A sound starts ([started]) or ends.
  void audio({required bool started}) {
    if (!active) return;
    (started ? _starts : _ends).add(_at());
  }

  /// Logs the line after the events of the same moment (a cancel follows
  /// the state change to idle); [abort] in between drops it.
  void finishSoon() {
    if (!active) return;
    final epoch = _epoch;
    scheduleMicrotask(() {
      if (epoch == _epoch) finish();
    });
  }

  /// Logs the line (only for a request whose transcript arrived) and resets.
  void finish() {
    if (active && _stt != null) {
      _log('latency', _fields());
    }
    abort();
  }

  /// Drops the time line without logging.
  void abort() {
    _epoch++;
    _t0 = null;
    _stt = null;
    _pendingReq = null;
    _calls.clear();
    _tools = 0;
    _tts1 = null;
    _synEnd = null;
    _syn.clear();
    _starts.clear();
    _ends.clear();
    _sentences = 0;
  }

  Map<String, Object?> _fields() {
    final f = <String, Object?>{
      'stt': _stt,
      'calls': _calls.length,
      'tools': _tools,
    };
    for (var i = 0; i < _calls.length && i < maxCalls; i++) {
      f['m${i + 1}_req'] = _calls[i].req;
      f['m${i + 1}_first'] = _calls[i].first;
      f['m${i + 1}_done'] = _calls[i].done;
    }
    f['tts1'] = _tts1;
    f['syn_end'] = _synEnd;
    f['audio_first'] = _starts.firstOrNull;
    f['audio_last'] = _ends.lastOrNull;
    f['sentences'] = _sentences;
    for (var i = 0; i < _syn.length && i < maxSentences; i++) {
      f['s${i + 1}_syn'] = _syn[i];
    }
    for (var i = 1; i < _starts.length && i < maxSentences; i++) {
      if (i - 1 < _ends.length) {
        f['s${i + 1}_gap'] = _starts[i] - _ends[i - 1];
      }
    }
    return f;
  }
}

final class _Call {
  _Call(this.req);

  final Duration req;
  Duration? first;
  Duration? done;
}

/// The time line of the current request of this engine.
final latencyTraceProvider = Provider<LatencyTrace>((ref) => LatencyTrace());
