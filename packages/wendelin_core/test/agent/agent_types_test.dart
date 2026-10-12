import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  group('UserInput', () {
    test('defaults', () {
      final i = UserInput(text: 'Hallo');
      expect(i.images, isEmpty);
      expect(i.source, InputSource.text);
      expect(i.sttConfidence, isNull);
      expect(i.language, isNull);
      expect(i.requestEscalation, isFalse);
      expect(i.toString(), contains('Hallo'));
    });

    test('images are copied and unmodifiable', () {
      final images = [
        ImageBlock(mediaType: 'image/png', bytes: [1]),
      ];
      final i = UserInput(
        text: 'Was ist das?',
        images: images,
        source: InputSource.voice,
        sttConfidence: 0.7,
        language: 'de',
        requestEscalation: true,
      );
      images.clear();
      expect(i.images, hasLength(1));
      expect(i.images.clear, throwsUnsupportedError);
      expect(i.source, InputSource.voice);
      expect(i.sttConfidence, 0.7);
      expect(i.language, 'de');
      expect(i.requestEscalation, isTrue);
    });
  });

  group('AgentEvent', () {
    const call = ToolCallBlock(
      id: 'c1',
      name: 'calendar__delete_event',
      argumentsJson: '{}',
    );

    test('ConfirmationRequired forwards only the first answer', () {
      final answers = <bool>[];
      final e = ConfirmationRequired(
        call: call,
        description: 'Termin löschen',
        respond: answers.add,
      );
      expect(e.answered, isFalse);
      e
        ..respond(false)
        ..respond(true);
      expect(answers, [false]);
      expect(e.answered, isTrue);
      expect(e.toString(), contains('Termin löschen'));
    });

    test('EscalationConfirmationRequired forwards only the first answer', () {
      final answers = <bool>[];
      final e = EscalationConfirmationRequired(
        fromProfile: 'phala',
        toProfile: 'claude',
        reason: EscalationReason.modelGaveUp,
        respond: answers.add,
      );
      expect(e.answered, isFalse);
      e
        ..respond(true)
        ..respond(false)
        ..respond(true);
      expect(answers, [true]);
      expect(e.answered, isTrue);
      expect(e.fromProfile, 'phala');
      expect(e.toProfile, 'claude');
      expect(e.reason, EscalationReason.modelGaveUp);
      expect(e.toString(), contains('phala → claude'));
    });

    test('fields and toString of all variants', () {
      final outcome = ToolOutcome.text('ok');
      final events = <AgentEvent, String>{
        const Routed(profileId: 'p', modelId: 'm', reason: 'Standard'):
            'Standard',
        const AgentTextDelta('Hallo'): 'Hallo',
        const ToolCallStarted(call): 'calendar__delete_event',
        ToolCallFinished(
          call: call,
          outcome: outcome,
          duration: const Duration(milliseconds: 3),
        ): 'calendar__delete_event',
        const Escalated(
          fromProfile: 'a',
          toProfile: 'b',
          reason: EscalationReason.providerError,
        ): 'providerError',
        const UsageReported(
          profileId: 'p',
          modelId: 'm',
          usage: Usage(inputTokens: 1),
          costMicros: 7,
        ): 'in: 1',
        const Verification(
          profileId: 'p',
          status: VerificationStatus.verified,
          detail: 'r1',
        ): 'verified',
        const AgentDone(finalText: 'Fertig', stopReason: StopReason.endTurn):
            'Fertig',
        const AgentFailed(
          error: AgentErrorKind.cancelled,
          message: 'Abgebrochen',
          cause: CancelledException(),
        ): 'cancelled',
      };
      events.forEach((event, fragment) {
        expect(event.toString(), contains(fragment));
      });
      final finished = events.keys.whereType<ToolCallFinished>().single;
      expect(finished.outcome, same(outcome));
      expect(finished.duration, const Duration(milliseconds: 3));
      final failed = events.keys.whereType<AgentFailed>().single;
      expect(failed.cause, isA<CancelledException>());
      expect(ToolCallFinished(call: call, outcome: outcome).duration, isNull);
    });
  });
}
