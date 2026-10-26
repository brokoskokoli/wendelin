// WP148: Entwicklerlog – ohne Flag nichts, mit Flag Inhalt, Secrets geschwärzt.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/dev_agent_log.dart';
import 'package:wendelin/voice/dev_log.dart';
import 'package:wendelin/voice/latency_trace.dart';
import 'package:wendelin_core/wendelin_core.dart';

ToolCallBlock _call(int i, [String args = '{"name":"Licht"}']) =>
    ToolCallBlock(id: 'c$i', name: 'ha_call_$i', argumentsJson: args);

/// One tool round: call, result.
void _round(
  DevAgentTrace t,
  int i, {
  String args = '{"name":"Licht"}',
  String result = 'ok',
  bool error = false,
}) {
  t.event(ToolCallStarted(_call(i, args)));
  t.event(
    ToolCallFinished(
      call: _call(i, args),
      outcome: error ? ToolOutcome.error(result) : ToolOutcome.text(result),
      duration: const Duration(milliseconds: 40),
    ),
  );
}

void main() {
  late List<String> lines;

  setUp(() {
    lines = [];
    devLogSink = lines.add;
    devLogEnabled = false;
  });
  tearDown(() => devLogEnabled = false);

  group('devLog', () {
    test('ohne Flag keine Zeile und kein Inhalt', () {
      devLog('stt-text', {'text': 'Geheimer Satz'});
      final t = DevAgentTrace()
        ..event(const AgentTextDelta('Antwort mit Inhalt'))
        ..event(const AgentTextComplete());
      _round(t, 1, args: '{"x":"Inhalt"}', result: 'Inhalt');
      t.event(
        const AgentFailed(error: AgentErrorKind.toolRoundLimit, message: 'x'),
      );
      expect(lines, isEmpty);
    });

    test('mit Flag: Tag, Ereignis, Felder', () {
      devLogEnabled = true;
      devLog('stt-text', {
        'text': 'Schalte das Licht an',
        'conf': 0.9,
        'ok': true,
        'ms': const Duration(milliseconds: 12),
        'none': null,
      });
      expect(
        lines.single,
        'Wendelin/dev: stt-text engine=app text="Schalte das Licht an" '
        'conf=0.9 ok=true ms=12',
      );
    });

    test('lange Texte werden gekürzt, Zeilenumbrüche werden Leerzeichen', () {
      devLogEnabled = true;
      devLog('x', {'text': 'a\nb ${'c' * 1000}'});
      expect(lines.single, contains('a b ccc'));
      expect(lines.single.length, lessThan(devLogMaxChars + 80));
      expect(lines.single, contains('…(1004)'));
    });

    test('Secrets bleiben auch im Entwicklermodus geschwärzt', () {
      devLogEnabled = true;
      devLog('t', {
        'token': 'abc123SECRET',
        'apiKey': 'k-SECRET-1',
        'password': 'hunter2',
        'authorization': 'Bearer SECRETTOKEN',
        'header': 'Authorization: Bearer SECRETTOKEN',
        'text': 'Mein Passwort ist hunter2',
        'card': 'Karte 4111 1111 1111 1111',
        'url': 'https://x.test/a?api_key=SECRETQ&b=1',
        'sk': 'sk-ABCDEFGHIJKLMNOPQRSTUVWX',
        'args': devJson('{"password":"geheim99","note":"ok","auth":"zzz"}'),
      });
      final all = lines.single;
      for (final secret in [
        'abc123SECRET',
        'k-SECRET-1',
        'hunter2',
        'SECRETTOKEN',
        '4111',
        'SECRETQ',
        'ABCDEFGHIJKLMNOP',
        'geheim99',
        'zzz',
      ]) {
        expect(all, isNot(contains(secret)), reason: secret);
      }
      expect(all, contains('***'));
      expect(all, contains('note'));
    });
  });

  group('nur die Fundstelle wird geschwärzt', () {
    for (final (text, secret) in [
      ('Zahl mit Karte 4111 1111 1111 1111 bitte', '4111'),
      ('Überweise auf DE89 3704 0044 0532 0130 00 bitte', '0532'),
      ('Meine PIN 1234 merken', '1234'),
      ('Nimm den Key sk-ABCDEFGHIJKLMNOPQRSTUVWX heute', 'ABCDEFGH'),
    ]) {
      test(text, () {
        devLogEnabled = true;
        devLog('x', {'text': text});
        expect(lines.single, contains('text="'));
        expect(lines.single, contains('***'));
        expect(lines.single, isNot(contains(secret)));
        // Rest bleibt lesbar (Anfang und Ende des Satzes).
        expect(lines.single, contains(text.split(' ').first));
        expect(lines.single, contains(text.split(' ').last));
      });
    }
  });

  group('DevAgentTrace', () {
    test('Werkzeug, Argumente, Ergebnis und Modelltext sind sichtbar', () {
      devLogEnabled = true;
      final t = DevAgentTrace()
        ..event(const AgentTextDelta('Ich schalte '))
        ..event(const AgentTextDelta('das Licht.'));
      _round(t, 1, args: '{"name":"Wohnzimmer"}', result: 'Licht ist an');
      _round(t, 2, result: 'Gerät nicht gefunden', error: true);
      t
        ..event(const AgentTextDelta('Fertig.'))
        ..event(const AgentTextComplete());
      expect(lines, hasLength(6));
      expect(lines[0], contains('model-text'));
      expect(lines[0], contains('text="Ich schalte das Licht."'));
      expect(lines[1], contains('tool-call engine=app n=1 tool="ha_call_1"'));
      expect(lines[1], contains(r'Wohnzimmer'));
      expect(lines[2], contains('tool-result engine=app n=1'));
      expect(lines[2], contains('status="ok"'));
      expect(lines[2], contains('ms=40'));
      expect(lines[2], contains('result="Licht ist an"'));
      expect(lines[4], contains('status="error"'));
      expect(lines[5], contains('text="Fertig."'));
    });

    test(
      'observe verändert den Strom nicht: kein Warten auf die Flag-Lesung',
      () {
        fakeAsync((async) {
          var refreshed = 0;
          final got = <AgentEvent>[];
          const events = [AgentTextDelta('a'), AgentTextComplete()];
          DevAgentTrace()
              .observe(() => refreshed++, () => Stream.fromIterable(events))
              .listen(got.add);
          expect(refreshed, 1);
          async.flushMicrotasks(); // kein Timer, keine Datenbank nötig
          expect(got, events);
        });
      },
    );

    test('Abbruch nach 8 Runden: Zusammenfassung aller Runden', () {
      devLogEnabled = true;
      final t = DevAgentTrace();
      for (var i = 1; i <= 8; i++) {
        _round(t, i, result: 'Ergebnis $i');
      }
      lines.clear();
      t.event(
        const AgentFailed(
          error: AgentErrorKind.toolRoundLimit,
          message: 'zu viele Runden',
        ),
      );
      expect(
        lines.first,
        contains('agent-failed engine=app kind=toolRoundLimit'),
      );
      expect(lines.first, contains('rounds=8'));
      final rounds = lines.skip(1).toList();
      expect(rounds, hasLength(8));
      for (var i = 1; i <= 8; i++) {
        expect(rounds[i - 1], contains('$i ha_call_$i'));
        expect(rounds[i - 1], contains('Ergebnis $i'));
      }
    });

    test('begin vergisst die Runden der letzten Anfrage', () {
      devLogEnabled = true;
      final t = DevAgentTrace();
      _round(t, 1);
      t.begin();
      lines.clear();
      t.event(const AgentFailed(error: AgentErrorKind.provider, message: 'x'));
      expect(lines.single, contains('rounds=0'));
    });

    test('Passwort in Argumenten und Ergebnis wird geschwärzt', () {
      devLogEnabled = true;
      final t = DevAgentTrace();
      _round(
        t,
        1,
        args: '{"password":"hunter2","user":"anna"}',
        result: 'Das Passwort ist hunter2',
      );
      expect(lines.join('\n'), isNot(contains('hunter2')));
      expect(lines.join('\n'), contains('anna'));
    });
  });

  group('LatencyTrace', () {
    List<Map<String, Object?>> run() {
      final logged = <Map<String, Object?>>[];
      var clock = const Duration(seconds: 100);
      final trace = LatencyTrace(now: () => clock, log: (e, f) => logged.add(f))
        ..begin()
        ..sttDone();
      for (var i = 1; i <= 6; i++) {
        clock += const Duration(milliseconds: 100);
        trace
          ..agentEvent(
            const UsageReported(
              profileId: 'p',
              modelId: 'm',
              usage: Usage(inputTokens: 1, outputTokens: 1),
            ),
          )
          ..agentEvent(ToolCallStarted(_call(i)))
          ..agentEvent(
            ToolCallFinished(call: _call(i), outcome: ToolOutcome.text('x')),
          );
      }
      trace.finish();
      return logged;
    }

    test('ohne Flag nur die ersten 4 Aufrufe', () {
      final f = run().single;
      expect(f['calls'], 6);
      expect(f.containsKey('m4_req'), isTrue);
      expect(f.containsKey('m5_req'), isFalse);
    });

    test('mit Flag alle Runden', () {
      devLogEnabled = true;
      final f = run().single;
      expect(f.containsKey('m6_done'), isTrue);
    });
  });
}
