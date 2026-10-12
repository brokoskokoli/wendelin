import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// The invoker contract checker must reject broken event sequences.
void main() {
  const a = ToolCallBlock(id: 'a', name: 'x__y', argumentsJson: '{}');
  const b = ToolCallBlock(id: 'b', name: 'x__y', argumentsJson: '{}');
  const other = ToolCallBlock(id: 'z', name: 'x__y', argumentsJson: '{}');
  final ok = ToolOutcome.text('ok');
  ToolFinished fin(ToolCallBlock c) => ToolFinished(c, ok, Duration.zero);
  ConfirmationNeeded ask(ToolCallBlock c) =>
      ConfirmationNeeded(c, 'ok?', Completer<bool>());

  final valid = <String, List<ToolInvocationEvent>>{
    'sequential': [const ToolStarted(a), fin(a), const ToolStarted(b), fin(b)],
    'interleaved (parallel)': [
      const ToolStarted(a),
      const ToolStarted(b),
      fin(b),
      fin(a),
    ],
    'confirmation inside': [
      const ToolStarted(a),
      ask(a),
      fin(a),
      const ToolStarted(b),
      fin(b),
    ],
  };
  final invalid = <String, List<ToolInvocationEvent>>{
    'missing finished': [const ToolStarted(a), const ToolStarted(b), fin(b)],
    'missing started': [fin(a), const ToolStarted(b), fin(b)],
    'finished twice': [
      const ToolStarted(a),
      fin(a),
      fin(a),
      const ToolStarted(b),
      fin(b),
    ],
    'finished before started': [
      fin(a),
      const ToolStarted(a),
      const ToolStarted(b),
      fin(b),
    ],
    'confirmation after finished': [
      const ToolStarted(a),
      fin(a),
      ask(a),
      const ToolStarted(b),
      fin(b),
    ],
    'confirmation before started': [
      ask(a),
      const ToolStarted(a),
      fin(a),
      const ToolStarted(b),
      fin(b),
    ],
    'event for unknown call': [
      const ToolStarted(a),
      fin(a),
      const ToolStarted(b),
      fin(b),
      const ToolStarted(other),
    ],
  };

  valid.forEach((name, events) {
    test('accepts $name', () => expectWellFormedInvocation([a, b], events));
  });
  invalid.forEach((name, events) {
    test('rejects $name', () {
      expect(
        () => expectWellFormedInvocation([a, b], events),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}
