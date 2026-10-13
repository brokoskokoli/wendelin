import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  group('ToolOutcome', () {
    test('text factory', () {
      final o = ToolOutcome.text('fertig', summary: 'Termin angelegt');
      expect(o.isError, isFalse);
      expect(o.content, [const TextBlock('fertig')]);
      expect(o.text, 'fertig');
      expect(o.summary, 'Termin angelegt');
      expect(o.undo, isNull);
    });

    test('error factory', () {
      final o = ToolOutcome.error('Kalender fehlt', summary: 's');
      expect(o.isError, isTrue);
      expect(o.text, 'Kalender fehlt');
      expect(o.summary, 's');
    });

    test('declined is not an error, cancelled is', () {
      final d = ToolOutcome.declined();
      expect(d.isError, isFalse);
      expect(d.text, ToolOutcome.declinedText);
      final c = ToolOutcome.cancelled();
      expect(c.isError, isTrue);
      expect(c.text, ToolOutcome.cancelledText);
    });

    test('text joins only text blocks', () {
      final o = ToolOutcome(
        content: [
          const TextBlock('a'),
          ImageBlock(mediaType: 'image/png', bytes: [1]),
          const TextBlock('b'),
        ],
      );
      expect(o.text, 'ab');
      expect(o.isError, isFalse);
    });

    test('toResultBlock carries callId, content and isError', () {
      expect(
        ToolOutcome.error('x').toResultBlock('c1'),
        ToolResultBlock(
          callId: 'c1',
          content: const [TextBlock('x')],
          isError: true,
        ),
      );
      expect(ToolOutcome.text('y').toResultBlock('c2').isError, isFalse);
    });

    test('content is unmodifiable', () {
      final o = ToolOutcome(content: [const TextBlock('a')]);
      expect(() => o.content.add(const TextBlock('b')), throwsUnsupportedError);
      expect(o.toString(), contains('isError: false'));
    });

    test('UndoAction runs via call()', () async {
      var undone = 0;
      final u = UndoAction(label: 'Entfernen', run: () async => undone++);
      await u();
      await u.run();
      expect(undone, 2);
      expect(u.label, 'Entfernen');
    });
  });

  group('Integration value types', () {
    test('Availability', () {
      expect(Availability.yes.available, isTrue);
      const no = Availability(
        available: false,
        reason: 'App fehlt',
        storeUrl: 'https://play.google.com/x',
      );
      expect(
        no,
        const Availability(
          available: false,
          reason: 'App fehlt',
          storeUrl: 'https://play.google.com/x',
        ),
      );
      expect(
        no.hashCode,
        const Availability(
          available: false,
          reason: 'App fehlt',
          storeUrl: 'https://play.google.com/x',
        ).hashCode,
      );
      expect(
        no,
        isNot(
          const Availability(
            available: true,
            reason: 'App fehlt',
            storeUrl: 'https://play.google.com/x',
          ),
        ),
      );
      expect(
        no,
        isNot(
          const Availability(
            available: false,
            reason: 'x',
            storeUrl: 'https://play.google.com/x',
          ),
        ),
      );
      expect(
        no,
        isNot(const Availability(available: false, reason: 'App fehlt')),
      );
      expect(no.toString(), contains('App fehlt'));
    });

    test('SetupStep', () {
      const s = SetupStep(
        id: 'perm',
        kind: SetupStepKind.permission,
        label: 'Kalender',
      );
      expect(
        s,
        const SetupStep(
          id: 'perm',
          kind: SetupStepKind.permission,
          label: 'Kalender',
        ),
      );
      expect(
        s.hashCode,
        const SetupStep(
          id: 'perm',
          kind: SetupStepKind.permission,
          label: 'Kalender',
        ).hashCode,
      );
      expect(
        s,
        isNot(
          const SetupStep(
            id: 'x',
            kind: SetupStepKind.permission,
            label: 'Kalender',
          ),
        ),
      );
      expect(
        s,
        isNot(
          const SetupStep(
            id: 'perm',
            kind: SetupStepKind.login,
            label: 'Kalender',
          ),
        ),
      );
      expect(
        s,
        isNot(
          const SetupStep(
            id: 'perm',
            kind: SetupStepKind.permission,
            label: 'x',
          ),
        ),
      );
      expect(s.toString(), contains('perm'));
    });

    test('SetupState.complete iff nothing missing', () {
      expect(SetupState().complete, isTrue);
      expect(SetupState(missingSteps: ['perm']).complete, isFalse);
      expect(SetupState(missingSteps: ['a']), SetupState(missingSteps: ['a']));
      expect(
        SetupState(missingSteps: ['a']).hashCode,
        SetupState(missingSteps: ['a']).hashCode,
      );
      expect(
        SetupState(missingSteps: ['a']),
        isNot(SetupState(missingSteps: ['b'])),
      );
      expect(SetupState(missingSteps: ['a']).toString(), contains('a'));
    });
  });

  group('WP14 additions', () {
    const call = ToolCallBlock(id: 'c', name: 'x__y', argumentsJson: '{}');
    ToolContext ctx() => ToolContext(
      sessionId: 's',
      clock: FixedClock(DateTime.utc(2026)),
      locale: 'de-DE',
      timeZone: 'Europe/Berlin',
    );

    test('ConfirmationNeeded carries the effective risk', () {
      expect(
        ConfirmationNeeded(call, 'ok?', Completer<bool>()).risk,
        RiskLevel.external,
      );
      expect(
        ConfirmationNeeded(
          call,
          'ok?',
          Completer<bool>(),
          risk: RiskLevel.write,
        ).risk,
        RiskLevel.write,
      );
    });

    test('optional setup steps', () {
      const req = SetupStep(
        id: 'perm',
        kind: SetupStepKind.permission,
        label: 'Erlauben',
      );
      const opt = SetupStep(
        id: 'search',
        kind: SetupStepKind.config,
        label: 'Suchdienst',
        optional: true,
      );
      expect(opt, isNot(req));
      expect(
        opt,
        isNot(
          const SetupStep(
            id: 'search',
            kind: SetupStepKind.config,
            label: 'Suchdienst',
          ),
        ),
      );
      expect(opt.hashCode, isNot(req.hashCode));
      expect(opt.toString(), contains('optional'));
      expect(req.toString(), isNot(contains('optional')));
      expect(SetupState().requiredComplete(const [req, opt]), isTrue);
      expect(
        SetupState(missingSteps: ['search']).requiredComplete(const [req, opt]),
        isTrue,
      );
      expect(
        SetupState(missingSteps: ['search', 'perm'])
            .requiredComplete(const [req, opt]),
        isFalse,
      );
      expect(
        SetupState(missingSteps: ['unknown']).requiredComplete(const [opt]),
        isFalse,
      );
    });

    test('confirmationText falls back to describeForConfirmation', () async {
      expect(
        await const _ListEvents().confirmationText(const {}, ctx()),
        'Termine lesen',
      );
    });

    test('confirmationText uses the preparer', () async {
      final tool = FakeTool(
        name: 'x__y',
        prepare: (args, ctx) async => 'live ${ctx.timeZone}',
      );
      expect(
        await tool.confirmationText(const {}, ctx()),
        'live Europe/Berlin',
      );
    });

    test('failing, empty, slow or cancelled preparation falls back', () async {
      final failing = FakeTool(
        name: 'x__y',
        confirmation: (_) => 'sync',
        prepare: (args, ctx) => Future.error(StateError('weg')),
      );
      expect(await failing.confirmationText(const {}, ctx()), 'sync');
      final empty = FakeTool(
        name: 'x__y',
        confirmation: (_) => 'sync',
        prepare: (args, ctx) async => '  ',
      );
      expect(await empty.confirmationText(const {}, ctx()), 'sync');
      final never = FakeTool(
        name: 'x__y',
        confirmation: (_) => 'sync',
        prepare: (args, ctx) => Completer<String>().future,
      );
      expect(
        await never.confirmationText(
          const {},
          ctx(),
          timeout: const Duration(milliseconds: 10),
        ),
        'sync',
      );
      final cancelled = ctx()..cancel.cancel();
      expect(await never.confirmationText(const {}, cancelled), 'sync');
    });
  });

  group('ConfirmationNeeded', () {
    const call = ToolCallBlock(id: 'c', name: 'x__y', argumentsJson: '{}');
    test('respond is idempotent, first answer wins', () async {
      final e = ConfirmationNeeded(call, 'ok?', Completer<bool>());
      expect(e.answered, isFalse);
      e
        ..respond(false)
        ..respond(true);
      expect(e.answered, isTrue);
      expect(await e.decision.future, isFalse);
    });
    test('respond after external completion is ignored', () async {
      final e = ConfirmationNeeded(
        call,
        'ok?',
        Completer<bool>()..complete(true),
      );
      e.respond(false);
      expect(await e.decision.future, isTrue);
    });
  });

  group('Tool', () {
    test('spec extension mirrors name, description and schema', () {
      const tool = _ListEvents();
      expect(
        tool.spec,
        const ToolSpec(
          name: 'calendar__list_events',
          description: 'Listet Termine',
          inputSchema: {
            'type': 'object',
            'required': ['from'],
          },
        ),
      );
    });

    test('ToolContext creates a fresh CancelToken by default', () {
      final ctx = ToolContext(
        sessionId: 's',
        clock: FixedClock(DateTime.utc(2026)),
        locale: 'de-DE',
        timeZone: 'Europe/Berlin',
      );
      expect(ctx.cancel.isCancelled, isFalse);
      final token = CancelToken();
      expect(
        ToolContext(
          sessionId: 's',
          clock: const SystemClock(),
          locale: 'de',
          timeZone: 'UTC',
          cancel: token,
        ).cancel,
        same(token),
      );
    });
  });
}

/// Minimal hand-written [Tool] to show the interface is implementable.
final class _ListEvents implements Tool {
  const _ListEvents();

  @override
  String get name => 'calendar__list_events';

  @override
  String get description => 'Listet Termine';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'required': ['from'],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => ToolOutcome.text('keine Termine');

  @override
  String describeForConfirmation(Map<String, Object?> args) => 'Termine lesen';
}
