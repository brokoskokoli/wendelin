import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

/// One Server-Sent Event (`text/event-stream`).
@immutable
final class SseEvent {
  /// Creates an event.
  const SseEvent({required this.data, this.event, this.id});

  /// Value of the `event:` field, `null` if absent.
  final String? event;

  /// Joined `data:` lines (separated by `\n`).
  final String data;

  /// Value of the last `id:` field seen, `null` if none.
  final String? id;

  /// Whether this is the OpenAI-style end marker `data: [DONE]`.
  bool get isDone => data == '[DONE]';

  @override
  bool operator ==(Object other) =>
      other is SseEvent &&
      other.event == event &&
      other.data == data &&
      other.id == id;

  @override
  int get hashCode => Object.hash(event, data, id);

  @override
  String toString() => 'SseEvent(event: $event, id: $id, data: $data)';
}

/// Parses a byte stream in `text/event-stream` format into [SseEvent]s.
///
/// Follows the WHATWG rules: UTF-8 (also when a character is split across
/// chunks), line endings `\n`, `\r` and `\r\n` (also split across chunks),
/// comment lines (`:`), multi-line `data:`, one optional space after the
/// colon, events without data are dropped. Deviation for robustness: an
/// event still pending when the stream ends (no final blank line) is
/// emitted instead of discarded. Invalid UTF-8 ends the stream with a
/// [FormatException].
abstract final class SseParser {
  /// Parses [bytes] into events. Cancelling the returned stream cancels the
  /// subscription to [bytes] immediately (closing the HTTP connection).
  static Stream<SseEvent> parse(Stream<List<int>> bytes) {
    final state = _ParserState();
    return bytes
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .transform(
          StreamTransformer<String, SseEvent>.fromHandlers(
            handleData: state.line,
            handleDone: (sink) {
              state.flush(sink);
              sink.close();
            },
          ),
        );
  }
}

final class _ParserState {
  final StringBuffer _data = StringBuffer();
  var _hasData = false;
  String? _event;
  String? _lastId;
  var _first = true;

  void line(String raw, EventSink<SseEvent> sink) {
    var line = raw;
    if (_first) {
      _first = false;
      if (line.startsWith('\uFEFF')) line = line.substring(1);
    }
    if (line.isEmpty) {
      flush(sink);
      return;
    }
    if (line.startsWith(':')) return;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'data':
        if (_hasData) _data.write('\n');
        _data.write(value);
        _hasData = true;
      case 'event':
        _event = value;
      case 'id':
        if (!value.contains('\u0000')) _lastId = value;
    }
  }

  /// Dispatches the pending event (if it has data) and resets the buffers.
  void flush(EventSink<SseEvent> sink) {
    if (_hasData) {
      sink.add(SseEvent(data: _data.toString(), event: _event, id: _lastId));
    }
    _data.clear();
    _hasData = false;
    _event = null;
  }
}
