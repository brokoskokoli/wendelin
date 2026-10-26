import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/wake_enroller.dart';
import 'package:wendelin_voice/fakes.dart';

import '../../integration_test/support/enroll_log.dart';
import '../support/wake_support.dart';

String l(String event, [String fields = '']) =>
    'I/flutter: Wendelin/voice: $event engine=app $fields';

void main() {
  test('nur angenommene Aufnahmen: kein Befund', () {
    expect(
      enrollLogProblem([
        l('enroll-check', 'source=stt ok=true score=99 ms=40'),
        l('enroll-check', 'source=classifier ok=true score=99 ms=40'),
      ]),
      isNull,
    );
  });

  test('abgelehnte Aufnahme ist ein Befund', () {
    expect(
      enrollLogProblem([
        l('enroll-check', 'source=stt ok=true ms=40'),
        l('enroll-check', 'source=stt-no ok=false ms=40'),
      ]),
      contains('abgelehnt'),
    );
  });

  test('verworfener Ausreißer ist ein Befund', () {
    expect(
      enrollLogProblem([
        l('enroll-check', 'source=stt ok=true ms=40'),
        l('enroll-outlier', 'removed=1 left=14'),
      ]),
      contains('Ausreißer'),
    );
  });

  test(
    'ganz ohne enroll-check ist ein Befund (Log leer oder nicht erfasst)',
    () {
      expect(enrollLogProblem([]), contains('kein enroll-check'));
    },
  );

  test(
    'echter Einlerner: abgelehnter Clip steht als ok=false im Log',
    () async {
      final lines = <String>[];
      final old = voiceLogSink;
      voiceLogSink = lines.add;
      addTearDown(() => voiceLogSink = old);
      final e = WakeEnroller(
        audio: SequenceAudio([
          recording(),
          recording(),
          recording(),
          recording(),
        ]),
        features: fakeFeatures(),
        store: FakeWakeTemplateStore(),
        speakerId: 'a',
        target: 3,
        minimum: 2,
        pause: Duration.zero,
        verifier: FakeWakeVerifier(answer: (n) => n != 2),
      );
      await e.run();
      // Das Ziel wird trotzdem erreicht: nur rejected und das Log verraten es.
      expect(e.accepted, 3);
      expect(e.rejected, 1);
      expect(enrollLogProblem(lines), contains('abgelehnt'));
    },
  );
}
