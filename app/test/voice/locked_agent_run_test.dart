// WP53: Abbruch geht unabhängig vom Sperrzustand an den inneren Lauf.
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/locked_agent_run.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

final class _Inner implements AgentRun {
  int cancels = 0;

  @override
  Stream<AgentEvent> run(UserInput input) => const Stream.empty();

  @override
  void cancel() => cancels++;
}

final class _Scripted implements AgentRun {
  _Scripted(this.events);

  final List<AgentEvent> events;
  int cancels = 0;

  @override
  Stream<AgentEvent> run(UserInput input) => Stream.fromIterable(events);

  @override
  void cancel() => cancels++;
}

ToolCallFinished _finished(String name, ToolOutcome outcome) =>
    ToolCallFinished(
      call: ToolCallBlock(id: name, name: name, argumentsJson: '{}'),
      outcome: outcome,
    );

final _ok = ToolOutcome.text('ok');
final _unlock = ToolOutcome.error(
  'Entsperren nötig',
  summary: ToolExecutor.unlockSummary,
);
const _done = AgentDone(finalText: 'fertig', stopReason: StopReason.endTurn);

void main() {
  group('Modelllauf gesperrt (WP154 L2)', () {
    final refused = <String>[];
    final partly = <String>[];
    final access = <AccessContext>[];
    final commandAccess = <AccessContext>[];

    LockGateAgentRun gate({
      AgentRun? model,
      bool throws = false,
      LockedCommandResult command = LockedCommandResult.done,
    }) => LockGateAgentRun(
      inner: _Inner(),
      locked: () => true,
      runCommand: (_, _, a) async {
        commandAccess.add(a);
        return command;
      },
      onRefused: (t, input) => refused.add('$t:${input.text}'),
      onPartlyDone: partly.add,
      trigger: () => 'assistant',
      modelRun: (a) async {
        access.add(a);
        if (throws) throw StateError('x');
        return model;
      },
    );

    setUp(() {
      refused.clear();
      partly.clear();
      access.clear();
      commandAccess.clear();
    });

    Future<List<AgentEvent>> ask(LockGateAgentRun g, [String t = 'Licht an']) =>
        g.run(UserInput(text: t, language: 'de')).toList();

    test('kein Lauf: Entsperr-Satz und gemerkte Anfrage', () async {
      final events = await ask(gate());
      expect(
        (events.last as AgentDone).finalText,
        'Bitte entsperre das Telefon.',
      );
      expect(refused, ['assistant:Licht an']);
      expect(access.single, AccessContext.lockedUnknownVoice);
    });

    group('Stimme der Eingabe (WP154 L3)', () {
      Future<void> speak(LockGateAgentRun g, UserInput input) =>
          g.run(input).toList();

      test(
        'erkannte Person: Modelllauf und Befehl bekommen Stimme erkannt',
        () async {
          final known = UserInput(
            text: 'Licht an',
            source: InputSource.voice,
            speakerId: 'p1',
          );
          await speak(gate(), known);
          await speak(
            gate(),
            UserInput(
              text: 'Taschenlampe an',
              source: InputSource.voice,
              speakerId: 'p1',
            ),
          );
          expect(
            access.single,
            const AccessContext(locked: true, speakerRecognized: true),
          );
          expect(commandAccess.single.speakerRecognized, isTrue);
        },
      );

      test('ohne Id, getippt oder leere Id: fremd (fail-closed)', () async {
        for (final input in [
          UserInput(text: 'Licht an', source: InputSource.voice),
          UserInput(text: 'Licht an'),
          UserInput(text: 'Licht an', speakerId: 'p1'),
          UserInput(text: 'Licht an', source: InputSource.voice, speakerId: ''),
        ]) {
          await speak(gate(), input);
          await speak(
            gate(),
            UserInput(
              text: 'Taschenlampe an',
              source: input.source,
              speakerId: input.speakerId,
            ),
          );
        }
        expect(access, everyElement(AccessContext.lockedUnknownVoice));
        expect(commandAccess, everyElement(AccessContext.lockedUnknownVoice));
        expect(access, hasLength(4));
        expect(commandAccess, hasLength(4));
      });
    });

    test(
      'Fehler beim Bestimmen des Laufs: fail-closed wie kein Lauf',
      () async {
        final events = await ask(gate(throws: true));
        expect((events.last as AgentDone).finalText, contains('entsperre'));
        expect(refused, hasLength(1));
      },
    );

    test('Lauf: Ereignisse werden durchgereicht, nichts gemerkt', () async {
      final run = _Scripted([_finished('a', _ok), _done]);
      final events = await ask(gate(model: run));
      expect(events, run.events);
      expect(refused, isEmpty);
      expect(partly, isEmpty);
    });

    test('nur verweigerte Aufrufe: genau einmal gemerkt', () async {
      final run = _Scripted([
        _finished('b', _unlock),
        _finished('c', _unlock),
        _done,
      ]);
      await ask(gate(model: run));
      expect(refused, ['assistant:Licht an']);
      expect(partly, isEmpty);
    });

    for (final order in [
      ('erst erledigt, dann verweigert', true),
      ('erst verweigert, dann erledigt', false),
    ]) {
      test(
        '${order.$1}: Anfrage NICHT gemerkt (keine Doppelausführung)',
        () async {
          final run = _Scripted([
            if (order.$2) ...[
              _finished('licht', _ok),
              _finished('schloss', _unlock),
            ] else ...[
              _finished('schloss', _unlock),
              _finished('licht', _ok),
            ],
            _done,
          ]);
          await ask(gate(model: run));
          expect(refused, isEmpty, reason: 'sonst läuft das Licht doppelt');
          expect(partly, ['assistant'], reason: 'Entsperren wird angeboten');
        },
      );
    }

    test('Tool-Fehler ohne Verweigerung merkt nichts', () async {
      final run = _Scripted([
        _finished('a', ToolOutcome.error('kaputt')),
        _done,
      ]);
      await ask(gate(model: run));
      expect(refused, isEmpty);
      expect(partly, isEmpty);
    });

    test('Abbruch erreicht auch den gesperrten Lauf', () async {
      final run = _Scripted([_done]);
      final g = gate(model: run);
      await ask(g);
      g.cancel();
      expect(run.cancels, 1);
    });

    test(
      'Taschenlampenbefehl mit Stufe > A: Entsperr-Satz, gemerkt, kein Lauf',
      () async {
        final events = await ask(
          gate(command: LockedCommandResult.needsUnlock),
          'Taschenlampe an',
        );
        expect((events.last as AgentDone).finalText, contains('entsperre'));
        expect(refused, ['assistant:Taschenlampe an']);
        expect(access, isEmpty, reason: 'kein Modelllauf für einen Befehl');
      },
    );
  });

  for (final startLocked in [true, false]) {
    test('cancel erreicht den inneren Lauf (Start gesperrt=$startLocked)', () {
      final inner = _Inner();
      var locked = startLocked;
      final gate = LockGateAgentRun(
        inner: inner,
        locked: () => locked,
        runCommand: (_, _, _) async => LockedCommandResult.done,
        onRefused: (_, _) {},
        trigger: () => 'assistant',
      );
      locked = !startLocked; // Sperrzustand wechselt vor dem Abbruch
      gate.cancel();
      locked = startLocked;
      gate.cancel();
      expect(inner.cancels, 2);
    });
  }
}
