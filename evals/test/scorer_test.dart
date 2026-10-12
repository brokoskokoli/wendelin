import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

EvalCase _case(String expectYaml) => parseCaseFile('''
language: de
cases:
  - id: c
    prompt: p
    expect:
$expectYaml
''').single;

ObservedCall _call(String name, [Map<String, Object?>? args = const {}]) =>
    ObservedCall(name: name, args: args, rawArguments: '{kaputt');

void main() {
  final scorer = Scorer(EvalTime.parse('2026-10-14T09:00', defaultTimeZone));

  final tauchen = _case('''
      calls:
        - tool: calendar__create_event
          args:
            title: {contains: Tauchen}
            start: {at: "+1d 10:00"}
''');

  test('passender Aufruf (auch neben anderen) besteht', () {
    final r = scorer.score(
      tauchen,
      RunObservation(
        calls: [
          _call('calendar__list_calendars'),
          _call('calendar__create_event', {
            'title': 'X',
            'start': '2026-10-15T10:00',
          }),
          _call('calendar__create_event', {
            'title': 'Tauchen',
            'start': '2026-10-15T10:00',
          }),
        ],
      ),
    );
    expect(r.status, CaseStatus.passed);
    expect(r.reasons, isEmpty);
  });

  test('falsche Argumente nennen das Feld', () {
    final r = scorer.score(
      tauchen,
      RunObservation(
        calls: [
          _call('calendar__create_event', {
            'title': 'Tauchen',
            'start': '2026-10-15T11:00',
          }),
        ],
      ),
    );
    expect(r.status, CaseStatus.failed);
    expect(
      r.reasons.single,
      allOf(
        contains('Kein passender erfolgreicher Aufruf'),
        contains('start ist 2026-10-15T11:00'),
      ),
    );
  });

  test('fehlendes Argument', () {
    final r = scorer.score(
      tauchen,
      RunObservation(
        calls: [
          _call('calendar__create_event', {'title': 'Tauchen'}),
        ],
      ),
    );
    expect(r.reasons.single, contains('start fehlt'));
  });

  test('ungültiges JSON zählt als falsche Argumente', () {
    final r = scorer.score(
      tauchen,
      RunObservation(calls: [_call('calendar__create_event', null)]),
    );
    expect(r.reasons.single, contains('ungültiges Argument-JSON'));
    // Ohne Argument-Prädikate genügt der Tool-Name.
    final any = _case('''
      calls:
        - tool: clipboard__read
''');
    expect(
      scorer
          .score(any, RunObservation(calls: [_call('clipboard__read', null)]))
          .status,
      CaseStatus.passed,
    );
  });

  test('nicht aufgerufen', () {
    expect(
      scorer.score(tauchen, const RunObservation()).reasons.single,
      'Nicht aufgerufen: calendar__create_event(title enthält [Tauchen], '
      'start @ +1d 10:00) (aufgerufen: keine)',
    );
    expect(
      scorer
          .score(tauchen, RunObservation(calls: [_call('web__search')]))
          .reasons
          .single,
      endsWith('(aufgerufen: web__search)'),
    );
  });

  test('any_of: eine Alternative genügt', () {
    final c = _case('''
      calls:
        - any_of:
            - tool: alarms__set_timer
              args: {duration_seconds: 600}
            - tool: alarms__set_alarm
              args: {time: {clock: "09:10"}}
''');
    expect(
      scorer
          .score(
            c,
            RunObservation(
              calls: [
                _call('alarms__set_alarm', {'time': '9:10'}),
              ],
            ),
          )
          .status,
      CaseStatus.passed,
    );
    expect(
      scorer
          .score(
            c,
            RunObservation(
              calls: [
                _call('alarms__set_timer', {'duration_seconds': 60}),
              ],
            ),
          )
          .reasons
          .single,
      contains('alarms__set_timer: duration_seconds'),
    );
  });

  test('dotted path in Argumenten', () {
    final c = _case('''
      calls:
        - tool: x__y
          args:
            a.b: 1
''');
    expect(
      scorer
          .score(
            c,
            RunObservation(
              calls: [
                _call('x__y', {
                  'a': {'b': 1},
                }),
              ],
            ),
          )
          .status,
      CaseStatus.passed,
    );
    expect(
      scorer
          .score(
            c,
            RunObservation(
              calls: [
                _call('x__y', {'a': 1}),
              ],
            ),
          )
          .status,
      CaseStatus.failed,
    );
    expect(
      lookupPath({
        'a': {'b': null},
      }, 'a.b'),
      (true, null),
    );
    expect(lookupPath({'a': {}}, 'a.b'), (false, null));
  });

  test('no_tools und Antworttext', () {
    final c = _case('''
      no_tools: true
      text: {contains: "391"}
''');
    expect(
      scorer.score(c, const RunObservation(finalText: 'Das ist 391.')).status,
      CaseStatus.passed,
    );
    final r = scorer.score(
      c,
      RunObservation(calls: [_call('web__search')], finalText: 'weiß nicht'),
    );
    expect(r.reasons, [
      'Kein Tool erwartet, aufgerufen: web__search',
      'Antwort: „weiß nicht“ enthält nicht [391]',
    ]);
  });

  test('forbid und exact', () {
    final c = _case('''
      calls:
        - tool: calendar__delete_event
      forbid: [calendar__create_event]
      exact: true
''');
    final r = scorer.score(
      c,
      RunObservation(
        calls: [
          _call('calendar__list_events'),
          _call('calendar__delete_event'),
          _call('calendar__create_event'),
        ],
      ),
    );
    expect(r.reasons, [
      'Verbotenes Tool aufgerufen: calendar__create_event',
      'Zusätzliche Tools aufgerufen: calendar__list_events, calendar__create_event',
    ]);
  });

  test('Bestätigung erwartet bzw. verboten', () {
    final yes = _case('''
      calls: [{tool: calendar__delete_event}]
      confirmed: true
''');
    final call = [_call('calendar__delete_event')];
    expect(
      scorer.score(yes, RunObservation(calls: call, confirmations: 1)).status,
      CaseStatus.passed,
    );
    expect(
      scorer.score(yes, RunObservation(calls: call)).reasons.single,
      contains('Bestätigung erwartet'),
    );
    final no = _case('''
      calls: [{tool: calendar__delete_event}]
      confirmed: false
''');
    expect(
      scorer
          .score(no, RunObservation(calls: call, confirmations: 1))
          .reasons
          .single,
      contains('Unerwartete Bestätigung'),
    );
    expect(
      scorer.score(no, RunObservation(calls: call)).status,
      CaseStatus.passed,
    );
  });

  test('Abbruch des Agenten ist error', () {
    final r = scorer.score(
      tauchen,
      const RunObservation(
        failure: AgentFailed(error: AgentErrorKind.provider, message: 'kaputt'),
      ),
    );
    expect(r.status, CaseStatus.error);
    expect(r.reasons.single, 'Agent abgebrochen (provider): kaputt');
  });
  test('fehlgeschlagene Tool-Aufrufe erfüllen keine Erwartung (Review #1)', () {
    const failed = ObservedCall(
      name: 'calendar__create_event',
      args: {'title': 'Tauchen', 'start': '2026-10-15T10:00'},
      isError: true,
    );
    final r = scorer.score(tauchen, const RunObservation(calls: [failed]));
    expect(r.status, CaseStatus.failed);
    expect(r.reasons.single, contains('Tool meldete Fehler'));
    final ok = scorer.score(
      tauchen,
      RunObservation(
        calls: [
          failed,
          _call('calendar__create_event', {
            'title': 'Tauchen',
            'start': '2026-10-15T10:00',
          }),
        ],
      ),
    );
    expect(ok.status, CaseStatus.passed);
    final both = scorer.score(
      tauchen,
      const RunObservation(
        calls: [
          ObservedCall(
            name: 'calendar__create_event',
            args: {'title': 'X'},
            isError: true,
          ),
        ],
      ),
    );
    expect(both.reasons.single, contains('(Tool meldete Fehler)'));
  });

  test('succeeded: false akzeptiert auch fehlgeschlagene Aufrufe', () {
    final c = _case('''
      calls:
        - tool: calendar__delete_event
          succeeded: false
''');
    expect(
      scorer
          .score(
            c,
            const RunObservation(
              calls: [
                ObservedCall(
                  name: 'calendar__delete_event',
                  args: {},
                  isError: true,
                ),
              ],
            ),
          )
          .status,
      CaseStatus.passed,
    );
    expect(
      () => _case('''
      calls:
        - tool: x
          succeeded: ja
'''),
      throwsFormatException,
    );
  });
}
