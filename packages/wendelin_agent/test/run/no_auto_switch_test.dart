// WP59 / K28: Wendelin never switches to another provider on its own. The
// chosen target answers or the run fails with a reason; only an explicit
// user request („nochmal mit …“) changes the provider.

import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

void main() {
  group('errors end the run at the chosen target', () {
    final cases = <(String, ProviderException, int, String)>[
      (
        'offline',
        const NetworkException('weg'),
        2,
        'Claude ist gerade nicht erreichbar.',
      ),
      (
        '503',
        const ServerException('overloaded', statusCode: 503),
        2,
        'Claude ist gerade überlastet oder gestört.',
      ),
      (
        '429',
        const RateLimitException('zu viel'),
        2,
        'Claude hat das Kontingent erreicht (zu viele Anfragen).',
      ),
      (
        'timeout',
        const ProviderTimeoutException('langsam'),
        2,
        'Claude antwortet nicht rechtzeitig.',
      ),
      (
        'unknown model',
        const InvalidRequestException('model x'),
        1,
        'Claude kennt das Modell oder die Anfrage nicht.',
      ),
      (
        '401',
        const AuthException('key'),
        1,
        'Claude hat den Zugang abgelehnt. Bitte den API-Schlüssel prüfen.',
      ),
      (
        'check red',
        const AttestationFailedException('rot', stage: 'receipt.signature'),
        1,
        'Die Prüfung von Claude ist fehlgeschlagen.',
      ),
      (
        'check not completed',
        const AttestationFailedException(
          'offen',
          stage: 'quote',
          unavailable: true,
        ),
        2,
        'Die Prüfung von Claude ist fehlgeschlagen.',
      ),
    ];

    for (final (name, error, calls, message) in cases) {
      test('$name: $calls call(s) at the target, none at the other', () async {
        final (a, pa) = scripted('a', [
          ScriptedTurn.error(error),
          ScriptedTurn.error(error),
        ], name: 'Claude');
        final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
        final events = await Harness(primary: a, chain: [b]).run('x');

        expect(pa.requests, hasLength(calls));
        expect(pb.requests, isEmpty);
        expect(events.whereType<Escalated>(), isEmpty);
        expect(events.whereType<EscalationConfirmationRequired>(), isEmpty);
        final end = terminal(events) as AgentFailed;
        expect(end.error, AgentErrorKind.provider);
        expect(end.message, message);
        expect(end.cause, error);
      });
    }

    test(
      'after a failed check and a network error: still no second call',
      () async {
        // WP52 review: a repeated „not verifiable“ run followed by a network
        // error once reached the second provider.
        const unverified = AttestationFailedException(
          'offen',
          stage: 'quote',
          unavailable: true,
        );
        const down = NetworkException('weg');
        final (tee, pt) = scripted('phala', [
          ScriptedTurn.error(unverified),
          ScriptedTurn.error(unverified),
          ScriptedTurn.error(down),
          ScriptedTurn.error(down),
        ], privacy: PrivacyLevel.tee);
        final (std, ps) = scripted('claude', [ScriptedTurn.text('nie')]);
        final h = Harness(primary: tee, chain: [std]);
        final first = await h.run('x');
        final second = await h.run('y');
        expect(pt.requests, hasLength(4));
        expect(ps.requests, isEmpty);
        expect((terminal(first) as AgentFailed).error, AgentErrorKind.provider);
        expect(
          (terminal(second) as AgentFailed).error,
          AgentErrorKind.provider,
        );
        expect(second.whereType<Escalated>(), isEmpty);
      },
    );

    test('a transient error is retried once at the same target', () async {
      final (a, pa) = scripted('a', [
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.text('Da.'),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
      final events = await Harness(primary: a, chain: [b]).run('x');
      expect(pa.requests, hasLength(2));
      expect(pb.requests, isEmpty);
      expect((terminal(events) as AgentDone).finalText, 'Da.');
    });

    test('a private request fails the same way (no question)', () async {
      final (tee, _) = scripted('phala', [
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.error(const NetworkException('weg')),
      ], privacy: PrivacyLevel.tee);
      final (std, ps) = scripted('claude', [ScriptedTurn.text('nie')]);
      final h = Harness(primary: tee, chain: [std], isPrivate: (_) => true);
      final events = await h.run('x');
      expect(ps.requests, isEmpty);
      expect(events.whereType<EscalationConfirmationRequired>(), isEmpty);
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.provider);
    });
  });

  group('answers are not a reason to switch', () {
    test('„kann ich nicht“ stands as the answer', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.text('Das kann ich leider nicht.'),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
      final events = await Harness(primary: a, chain: [b]).run('x');
      expect(pb.requests, isEmpty);
      expect(events.whereType<Escalated>(), isEmpty);
      expect(
        (terminal(events) as AgentDone).finalText,
        'Das kann ich leider nicht.',
      );
    });

    test('repeated invalid tool calls stay at the target', () async {
      final tool = FakeTool(name: 'cal__create');
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'cal__erstellen', '{}')]),
        ScriptedTurn.toolCalls([call('c2', 'cal__create', '{"title":')]),
        ScriptedTurn.toolCalls([call('c3', 'cal__erstellen', '{"x":1}')]),
        ScriptedTurn.text('A gibt auf.'),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
      final events = await Harness(
        primary: a,
        chain: [b],
        tools: [tool],
      ).run('x');
      expect(pb.requests, isEmpty);
      expect(events.whereType<Escalated>(), isEmpty);
      expect((terminal(events) as AgentDone).finalText, 'A gibt auf.');
    });

    test('many rounds without result run to the round limit', () async {
      final tool = FakeTool(name: 'web__search');
      final (a, pa) = scripted('a', [
        for (var i = 1; i <= 12; i++)
          ScriptedTurn.toolCalls([call('a$i', 'web__search', '{"n":$i}')]),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
      final events = await Harness(
        primary: a,
        chain: [b],
        tools: [tool],
      ).run('x');
      expect(pb.requests, isEmpty);
      expect(pa.requests, hasLength(9));
      expect(
        (terminal(events) as AgentFailed).error,
        AgentErrorKind.toolRoundLimit,
      );
    });
  });

  group('explicit request still switches', () {
    test('„nochmal mit Claude“ goes to the named target at once', () async {
      final (a, pa) = scripted('a', [ScriptedTurn.text('nie')]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('B hier.')]);
      final events = await Harness(
        primary: a,
        chain: [b],
      ).run('nochmal mit Claude', requestEscalation: true);
      final esc = events.whereType<Escalated>().single;
      expect(esc.reason, EscalationReason.userRequested);
      expect(pa.requests, isEmpty);
      expect(pb.requests, hasLength(1));
      expect((terminal(events) as AgentDone).finalText, 'B hier.');
    });

    test('an error of the requested target does not switch again', () async {
      final (a, pa) = scripted('a', [ScriptedTurn.text('nie')]);
      final (b, pb) = scripted('b', [
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.error(const NetworkException('weg')),
      ]);
      final (c, pc) = scripted('c', [ScriptedTurn.text('nie')]);
      final events = await Harness(
        primary: a,
        chain: [b, c],
      ).run('nochmal mit B', requestEscalation: true);
      expect(pa.requests, isEmpty);
      expect(pb.requests, hasLength(2));
      expect(pc.requests, isEmpty);
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.provider);
    });
  });
}
