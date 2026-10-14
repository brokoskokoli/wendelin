// Hand-over on the user's request („nochmal mit …“): privacy consent (K28).

import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

void main() {
  group('hand-over on request', () {
    test('privacy boundary: tee → standard needs consent, declined', () async {
      final (tee, pt) = scripted('phala', [
        ScriptedTurn.text('Phala bleibt.'),
      ], privacy: PrivacyLevel.tee);
      final (std, ps) = scripted('claude', [ScriptedTurn.text('Claude hier.')]);
      final h = Harness(
        primary: tee,
        chain: [std],
        isPrivate: (i) => i.text.contains('privat'),
      );
      final events = await h.run(
        'privat: Wie ist mein Kontostand?',
        requestEscalation: true,
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) e.respond(false);
        },
      );
      expect(pt.requests, isEmpty);
      expect(ps.requests, isEmpty);
      final question = events
          .whereType<EscalationConfirmationRequired>()
          .single;
      expect(
        (question.fromProfile, question.toProfile, question.reason),
        ('phala', 'claude', EscalationReason.userRequested),
      );
      expect(events.whereType<Escalated>(), isEmpty);
      // K28: the user declined; the first target does not answer instead.
      expect((terminal(events) as AgentFailed).message, startsWith('Nicht'));
      expect((events.first as Routed).reason, 'Privat');
    });

    test('privacy boundary: consent given → standard answers', () async {
      final (tee, pt) = scripted('phala', [
        ScriptedTurn.text('nie'),
      ], privacy: PrivacyLevel.tee);
      final (std, ps) = scripted('claude', [ScriptedTurn.text('Claude hier.')]);
      final h = Harness(
        primary: tee,
        chain: [std],
        isPrivate: (i) => i.text.contains('privat'),
      );
      final events = await h.run(
        'privat: x',
        requestEscalation: true,
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) e.respond(true);
        },
      );
      expect(pt.requests, isEmpty);
      expect(ps.requests, hasLength(1));
      expect(events.whereType<Escalated>().single.toProfile, 'claude');
      expect(terminal(events), isA<AgentDone>());
    });

    test('privacy boundary: no question for a non-private request', () async {
      final (tee, _) = scripted('phala', [
        ScriptedTurn.text('nie'),
      ], privacy: PrivacyLevel.tee);
      final (std, ps) = scripted('claude', [ScriptedTurn.text('Claude hier.')]);
      final h = Harness(
        primary: tee,
        chain: [std],
        isPrivate: (i) => i.text.contains('privat'),
      );
      final events = await h.run('Wetter?', requestEscalation: true);
      expect(events.whereType<EscalationConfirmationRequired>(), isEmpty);
      expect(ps.requests, hasLength(1));
    });

    test('a declined hand-over sends nothing, no error follows', () async {
      final (tee, pt) = scripted('phala', [
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.error(const NetworkException('weg')),
      ], privacy: PrivacyLevel.tee);
      final (std, ps) = scripted('claude', [ScriptedTurn.text('nie')]);
      final h = Harness(primary: tee, chain: [std], isPrivate: (_) => true);
      final events = await h.run(
        'x',
        requestEscalation: true,
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) e.respond(false);
        },
      );
      expect(events.whereType<EscalationConfirmationRequired>(), hasLength(1));
      expect(pt.requests, isEmpty);
      expect(ps.requests, isEmpty);
      expect((terminal(events) as AgentFailed).message, startsWith('Nicht'));
    });

    test('cancel while the question is pending', () async {
      final (tee, _) = scripted('phala', [
        ScriptedTurn.text('nie'),
      ], privacy: PrivacyLevel.tee);
      final (std, ps) = scripted('claude', [ScriptedTurn.text('nie')]);
      final h = Harness(primary: tee, chain: [std], isPrivate: (_) => true);
      final events = await h.run(
        'x',
        requestEscalation: true,
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) h.runner.cancel();
        },
      );
      expect(ps.requests, isEmpty);
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.cancelled);
      expect(
        events.whereType<EscalationConfirmationRequired>().single.answered,
        isTrue,
      );
    });

    test('an abort while the question is open wins over a „Ja“', () async {
      // M17: answered „Ja“, then cancelled before the run resumed – no
      // hand-over, the run ends as cancelled.
      final (tee, _) = scripted('phala', [
        ScriptedTurn.text('nie'),
      ], privacy: PrivacyLevel.tee);
      final (std, ps) = scripted('claude', [ScriptedTurn.text('nie')]);
      final h = Harness(primary: tee, chain: [std], isPrivate: (_) => true);
      final events = await h.run(
        'x',
        requestEscalation: true,
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) {
            e.respond(true);
            h.runner.cancel();
          }
        },
      );
      expect(events.whereType<Escalated>(), isEmpty);
      expect(ps.requests, isEmpty);
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.cancelled);
    });

    test(
      'user requested escalation starts with the requested target',
      () async {
        final (a, pa) = scripted('a', [ScriptedTurn.text('nie')]);
        final (b, pb) = scripted('b', [ScriptedTurn.text('B hier.')]);
        final h = Harness(primary: a, chain: [b]);
        final events = await h.run(
          'nochmal mit Claude',
          requestEscalation: true,
        );
        expect(events.first, isA<Routed>());
        expect(events[1], isA<Escalated>());
        expect((events[1] as Escalated).reason, EscalationReason.userRequested);
        expect(pa.requests, isEmpty);
        expect(pb.requests, hasLength(1));
        expect(pb.requests.single.systemPrompt, isNot(contains('Übergabe')));
      },
    );
  });
}
