// WP128: after a provider failure the user is offered another configured
// provider („Mit X nochmal?“): never automatic (K28), never below the
// privacy level of the failed one, never after a cancel or budget stop, and
// only the model call is repeated (tools never run twice).

import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

const _down = NetworkException('weg');

List<ScriptedTurn> _fails([ProviderException e = _down]) => [
  ScriptedTurn.error(e),
  ScriptedTurn.error(e),
];

void main() {
  group('offer after a provider failure', () {
    test('yes: only the second provider answers, an event marks it', () async {
      final (a, pa) = scripted('a', _fails(), name: 'Anbieter A');
      final (b, pb) = scripted('b', [ScriptedTurn.text('B hier.')]);
      final h = Harness(primary: a, fallbackTargets: () => [b]);
      final events = await h.run(
        'Hallo',
        onEvent: (e) {
          if (e is RetryOfferRequired) e.respond(true);
        },
      );
      final offer = events.whereType<RetryOfferRequired>().single;
      expect((offer.fromProfile, offer.toProfile), ('a', 'b'));
      expect(offer.error, _down);
      expect(pa.requests, hasLength(2)); // first try + the one retry
      expect(pb.requests, hasLength(1));
      final escalated = events.whereType<Escalated>().single;
      expect(escalated.reason, EscalationReason.providerFailed);
      expect((terminal(events) as AgentDone).finalText, 'B hier.');
    });

    test('no answer from the user yet: nothing goes to the offered', () async {
      final (a, _) = scripted('a', _fails());
      final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
      final h = Harness(primary: a, fallbackTargets: () => [b]);
      final events = await h.run(
        'Hallo',
        onEvent: (e) {
          if (e is RetryOfferRequired) {
            // Nothing is sent before the answer.
            expect(pb.requests, isEmpty);
            e.respond(false);
          }
        },
      );
      expect(pb.requests, isEmpty);
      expect(events.whereType<Escalated>(), isEmpty);
      final failed = terminal(events) as AgentFailed;
      expect(failed.error, AgentErrorKind.provider);
      expect(failed.cause, _down);
    });

    test('no fallback configured: failure as before, no offer', () async {
      final (a, _) = scripted('a', _fails());
      final h = Harness(primary: a);
      final events = await h.run('Hallo');
      expect(events.whereType<RetryOfferRequired>(), isEmpty);
      expect(terminal(events), isA<AgentFailed>());
    });

    for (final (name, e) in <(String, ProviderException)>[
      ('timeout', const ProviderTimeoutException('langsam')),
      ('network', _down),
      ('503', const ServerException('down', statusCode: 503)),
      (
        'tee check',
        const AttestationFailedException('rot', stage: 'receipt.signature'),
      ),
    ]) {
      test('offered for $name', () async {
        final (a, _) = scripted('a', _fails(e));
        final (b, _) = scripted('b', [ScriptedTurn.text('ok')]);
        final h = Harness(primary: a, fallbackTargets: () => [b]);
        final events = await h.run(
          'Hallo',
          onEvent: (x) {
            if (x is RetryOfferRequired) x.respond(false);
          },
        );
        expect(events.whereType<RetryOfferRequired>(), hasLength(1));
      });
    }

    for (final (name, e) in <(String, ProviderException)>[
      ('401', const AuthException('key')),
      ('400', const InvalidRequestException('x')),
      ('429', const RateLimitException('zu viel')),
      ('404 server', const ServerException('x', statusCode: 404)),
      ('malformed', const MalformedResponseException('x')),
      ('gpu dialog', const AttestationFailedException('gpu', stage: 'gpu')),
    ]) {
      test('not offered for $name', () async {
        final (a, _) = scripted('a', _fails(e));
        final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
        final h = Harness(primary: a, fallbackTargets: () => [b]);
        final events = await h.run('Hallo');
        expect(events.whereType<RetryOfferRequired>(), isEmpty);
        expect(pb.requests, isEmpty);
        expect(
          (terminal(events) as AgentFailed).error,
          AgentErrorKind.provider,
        );
      });
    }

    test('user cancel while the call fails: no offer', () async {
      final (a, _) = scripted('a', _fails());
      final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
      late Harness h;
      h = Harness(primary: a, fallbackTargets: () => [b]);
      final events = await h.run(
        'Hallo',
        onEvent: (e) {
          if (e is Routed) h.runner.cancel();
        },
      );
      expect(events.whereType<RetryOfferRequired>(), isEmpty);
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.cancelled);
      expect(pb.requests, isEmpty);
    });

    test('cancel while the offer is open ends the run, B untouched', () async {
      final (a, _) = scripted('a', _fails());
      final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
      late Harness h;
      h = Harness(primary: a, fallbackTargets: () => [b]);
      final events = await h.run(
        'Hallo',
        onEvent: (e) {
          if (e is RetryOfferRequired) h.runner.cancel();
        },
      );
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.cancelled);
      expect(pb.requests, isEmpty);
    });

    test('budget stop is no provider failure: no offer', () async {
      final (a, pa) = scripted('a', [ScriptedTurn.text('nie')]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
      final h = Harness(
        primary: a,
        fallbackTargets: () => [b],
        budget: FixedBudgetGuard(
          const BudgetCheck.block(spentMicros: 11, budgetMicros: 10),
        ),
      );
      final events = await h.run('Hallo');
      expect(events.whereType<RetryOfferRequired>(), isEmpty);
      expect(
        (terminal(events) as AgentFailed).error,
        AgentErrorKind.budgetBlocked,
      );
      expect(pa.requests, isEmpty);
      expect(pb.requests, isEmpty);
    });
  });

  group('privacy level of the offer', () {
    test('tee run is never offered a standard (cloud) provider', () async {
      final (a, _) = scripted('phala', _fails(), privacy: PrivacyLevel.tee);
      final (cloud, pc) = scripted('claude', [ScriptedTurn.text('nie')]);
      final (eu, pe) = scripted('mistral', [
        ScriptedTurn.text('nie'),
      ], privacy: PrivacyLevel.eu);
      final h = Harness(
        primary: a,
        fallbackTargets: () => [cloud, eu],
        isPrivate: (i) => true,
      );
      final events = await h.run('privat: Hallo');
      expect(events.whereType<RetryOfferRequired>(), isEmpty);
      expect(pc.requests, isEmpty);
      expect(pe.requests, isEmpty);
    });

    test('the first target of at least the same level is offered', () async {
      final (a, _) = scripted('phala', _fails(), privacy: PrivacyLevel.tee);
      final (cloud, pc) = scripted('claude', [ScriptedTurn.text('nie')]);
      final (tinfoil, pt) = scripted('tinfoil', [
        ScriptedTurn.text('Tinfoil hier.'),
      ], privacy: PrivacyLevel.tee);
      final h = Harness(
        primary: a,
        fallbackTargets: () => [cloud, tinfoil],
        isPrivate: (i) => true,
      );
      final events = await h.run(
        'privat: Hallo',
        onEvent: (e) {
          if (e is RetryOfferRequired) {
            expect(e.toProfile, 'tinfoil');
            e.respond(true);
          }
        },
      );
      expect(pc.requests, isEmpty);
      expect(pt.requests, hasLength(1));
      expect((terminal(events) as AgentDone).finalText, 'Tinfoil hier.');
    });

    test('a stronger target is fine', () async {
      final (a, _) = scripted('claude', _fails());
      final (local, _) = scripted('ollama', [
        ScriptedTurn.text('lokal'),
      ], privacy: PrivacyLevel.local);
      final h = Harness(primary: a, fallbackTargets: () => [local]);
      final events = await h.run(
        'Hallo',
        onEvent: (e) {
          if (e is RetryOfferRequired) e.respond(true);
        },
      );
      expect((terminal(events) as AgentDone).finalText, 'lokal');
    });
  });

  group('only the model call is repeated', () {
    test('tools that ran are not run again at the second provider', () async {
      final tool = FakeTool(
        name: 'lists__add',
        outcome: ToolOutcome.text('hinzugefügt'),
      );
      final (a, pa) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'lists__add')]),
        ..._fails(),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('Erledigt.')]);
      final h = Harness(primary: a, tools: [tool], fallbackTargets: () => [b]);
      final events = await h.run(
        'Setz Milch auf die Liste',
        onEvent: (e) {
          if (e is RetryOfferRequired) e.respond(true);
        },
      );
      expect(tool.calls, hasLength(1));
      expect(events.whereType<ToolCallStarted>(), hasLength(1));
      // B sees the result of the tool that already ran.
      expect(lastResults(pb.requests.single).single.callId, 'c1');
      expect((terminal(events) as AgentDone).finalText, 'Erledigt.');
    });

    test('the second provider fails too: no way back to the first', () async {
      final (a, pa) = scripted('a', _fails());
      final (b, pb) = scripted('b', _fails());
      final h = Harness(primary: a, fallbackTargets: () => [a, b]);
      var offers = 0;
      final events = await h.run(
        'Hallo',
        onEvent: (e) {
          if (e is RetryOfferRequired) {
            offers++;
            e.respond(true);
          }
        },
      );
      expect(offers, 1);
      expect(pa.requests, hasLength(2));
      expect(pb.requests, hasLength(2));
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.provider);
    });
  });
}
