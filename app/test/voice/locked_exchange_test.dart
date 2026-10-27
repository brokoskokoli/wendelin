// WP163 (ADR 0022 L2/L3): the locked overlay may show the current request
// and the answer that is spoken anyway, nothing else.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/locked_agent_run.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';
import 'package:wendelin_voice/wendelin_voice.dart' show VoiceTexts;

final class _Inner implements AgentRun {
  @override
  Stream<AgentEvent> run(UserInput input) => const Stream.empty();

  @override
  void cancel() {}
}

final class _Model implements AgentRun {
  _Model(this.events);

  final Stream<AgentEvent> events;

  @override
  Stream<AgentEvent> run(UserInput input) => events;

  @override
  void cancel() {}
}

ToolCallFinished _finished(ToolOutcome outcome, {String name = 'ha__call'}) =>
    ToolCallFinished(
      call: ToolCallBlock(
        id: name,
        name: name,
        argumentsJson: '{"k":"geheim"}',
      ),
      outcome: outcome,
    );

final _unlock = ToolOutcome.error(
  'Entsperren nötig',
  summary: ToolExecutor.unlockSummary,
);

AgentEvent _done(String t) =>
    AgentDone(finalText: t, stopReason: StopReason.endTurn);

void main() {
  late ProviderContainer c;
  late bool locked;

  LockedExchange? exchange() => c.read(lockedExchangeProvider);

  LockGateAgentRun gate({
    Stream<AgentEvent>? model,
    LockedCommandResult command = LockedCommandResult.done,
  }) => LockGateAgentRun(
    inner: _Inner(),
    locked: () => locked,
    runCommand: (_, _, _) async => command,
    onRefused: (_, _) {},
    trigger: () => 'assistant',
    modelRun: (_) async => model == null ? null : _Model(model),
    onRequest: (i) => c.read(lockedExchangeProvider.notifier).begin(i.text),
    onAnswer: (t) => c.read(lockedExchangeProvider.notifier).answer(t),
  );

  Future<void> ask(LockGateAgentRun g, String text) =>
      g.run(UserInput(text: text, language: 'de')).toList();

  setUp(() {
    c = ProviderContainer();
    locked = true;
  });
  tearDown(() => c.dispose());

  test('Modellantwort aus erlaubtem Lauf: Anfrage und Antworttext', () async {
    await ask(
      gate(
        model: Stream.fromIterable([
          _finished(ToolOutcome.text('ok')),
          const AgentTextDelta('Licht'),
          _done('Licht ist an.'),
        ]),
      ),
      'Licht an',
    );
    expect(exchange()?.request, 'Licht an');
    expect(exchange()?.answer, 'Licht ist an.');
  });

  test('zweite Anfrage ersetzt die erste, kein Verlauf', () async {
    final g = gate(model: Stream.fromIterable([_done('Antwort 1')]));
    await ask(g, 'erste');
    final g2 = gate(model: Stream.fromIterable([_done('Antwort 2')]));
    await ask(g2, 'zweite');
    expect(exchange()?.request, 'zweite');
    expect(exchange()?.answer, 'Antwort 2');
  });

  test('neue Anfrage: alte Antwort ist sofort weg (Antwort offen)', () async {
    await ask(gate(model: Stream.fromIterable([_done('alt')])), 'erste');
    final never = StreamController<AgentEvent>();
    final sub = gate(model: never.stream)
        .run(UserInput(text: 'zweite', language: 'de'))
        .listen((_) {});
    await pumpEventQueue();
    expect(exchange()?.request, 'zweite');
    expect(exchange()?.answer, isNull);
    unawaited(sub.cancel());
    never.add(const AgentTextDelta('x'));
    unawaited(never.close());
  });

  test('Verweigerung ohne Lauf: nur der feste Satz', () async {
    await ask(gate(), 'Mein Kontostand');
    expect(exchange()?.request, 'Mein Kontostand');
    expect(exchange()?.answer, 'Bitte entsperre das Telefon.');
  });

  test('Befehl: fester Satz, Verweigerung: Entsperr-Satz', () async {
    await ask(gate(), 'Taschenlampe an');
    expect(exchange()?.answer, 'Taschenlampe an.');
    await ask(
      gate(command: LockedCommandResult.needsUnlock),
      'Taschenlampe aus',
    );
    expect(exchange()?.answer, 'Bitte entsperre das Telefon.');
    await ask(gate(command: LockedCommandResult.failed), 'Taschenlampe an');
    expect(exchange()?.answer, 'Das hat nicht geklappt.');
  });

  test('teilweise erledigt: nur der gesprochene Antworttext, keine '
      'Werkzeugdetails', () async {
    await ask(
      gate(
        model: Stream.fromIterable([
          _finished(ToolOutcome.text('Ergebnis-Geheimnis')),
          _finished(_unlock),
          _done('Licht an, für die Tür bitte entsperren.'),
        ]),
      ),
      'Licht an und Tür auf',
    );
    expect(exchange()?.answer, 'Licht an, für die Tür bitte entsperren.');
    final shown = '${exchange()?.request}|${exchange()?.answer}';
    expect(shown, isNot(contains('ha__call')));
    expect(shown, isNot(contains('geheim')));
    expect(shown, isNot(contains('Ergebnis')));
  });

  test(
    'Lauf scheitert: die gesprochene Fehlermeldung, nie das Detail',
    () async {
      await ask(
        gate(
          model: Stream.fromIterable([
            const AgentFailed(
              error: AgentErrorKind.provider,
              message: 'Keine Verbindung.',
              detail: 'secret-detail',
            ),
          ]),
        ),
        'Wetter',
      );
      expect(exchange()?.request, 'Wetter');
      expect(exchange()?.answer, 'Keine Verbindung.');
      expect(exchange()?.answer, isNot(contains('secret')));
    },
  );

  test(
    'Lauf scheitert in Englisch: derselbe Satz wie in der Sprachausgabe',
    () async {
      await gate(
        model: Stream.fromIterable([
          const AgentFailed(
            error: AgentErrorKind.timeout,
            message: 'Das dauert zu lange.',
          ),
        ]),
      ).run(UserInput(text: 'Weather', language: 'en')).toList();
      expect(exchange()?.answer, VoiceTexts.of('en').tooSlow);
    },
  );

  test(
    'Lauf abgebrochen (cancelled): keine Fehlermeldung als Antwort',
    () async {
      await ask(
        gate(
          model: Stream.fromIterable([
            const AgentFailed(
              error: AgentErrorKind.cancelled,
              message: 'Abgebrochen.',
            ),
          ]),
        ),
        'Wetter',
      );
      expect(exchange()?.answer, isNull);
    },
  );

  test(
    'gesprochener Kurztext statt Endtext (angezeigt = gesprochen)',
    () async {
      await ask(
        gate(
          model: Stream.fromIterable([
            const AgentSpokenText('Kurz: sonnig.'),
            _done('Lang: sonnig, 21 Grad, Wind aus West.'),
          ]),
        ),
        'Wetter',
      );
      expect(exchange()?.answer, 'Kurz: sonnig.');
    },
  );

  test(
    'Kurztext vor einem Werkzeugaufruf gilt nicht für den Endtext',
    () async {
      await ask(
        gate(
          model: Stream.fromIterable([
            const AgentSpokenText('Ich schaue nach.'),
            const ToolCallStarted(
              ToolCallBlock(id: 'c1', name: 'weather', argumentsJson: '{}'),
            ),
            _done('Es ist sonnig.'),
          ]),
        ),
        'Wetter',
      );
      expect(exchange()?.answer, 'Es ist sonnig.');
    },
  );

  test('Stream-Abbruch: Anfrage bleibt, Teiltext nicht als Antwort', () async {
    final events = StreamController<AgentEvent>();
    final sub = gate(model: events.stream)
        .run(UserInput(text: 'Wetter', language: 'de'))
        .listen((_) {});
    await pumpEventQueue();
    events.add(const AgentTextDelta('Teil'));
    await pumpEventQueue();
    // The generator stops at its next yield; the late final text of the
    // cancelled run must not show up.
    unawaited(sub.cancel());
    events.add(_done('Spaete Antwort'));
    await pumpEventQueue();
    expect(exchange()?.request, 'Wetter');
    expect(exchange()?.answer, isNull);
    unawaited(events.close());
  });

  test('entsperrt: nichts wird festgehalten', () async {
    locked = false;
    await ask(gate(), 'Licht an');
    expect(exchange(), isNull);
  });

  test('clear leert, answer ohne Anfrage wird ignoriert', () async {
    final n = c.read(lockedExchangeProvider.notifier)..answer('x');
    expect(exchange(), isNull);
    n.begin('a');
    n.answer('b');
    n.clear();
    expect(exchange(), isNull);
  });
}
