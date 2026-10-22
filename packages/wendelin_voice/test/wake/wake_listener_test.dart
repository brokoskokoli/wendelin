import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// 30 ms Frame mit fortlaufenden Sample-Werten ab [from].
Int16List counting(int from, [int n = 480]) =>
    Int16List.fromList([for (var i = 0; i < n; i++) (from + i) % 30000]);

void main() {
  late FakeAudioInput audio;
  late FakeWakeWordEngine engine;
  late FakeWakeVerifier verifier;
  late WakeWordListener listener;
  late List<WakeWordDetection> found;

  // Ohne Nachlauf, damit die Tests nicht auf 0,9 s Audio warten müssen.
  void setUpListener({
    WakeVerifier? v,
    Set<int> hits = const {},
    Duration tail = Duration.zero,
    Duration acceptDelay = Duration.zero,
  }) {
    // Die Tests prüfen den Inhalt der Samples; die Pegelnormalisierung der
    // Stufe 2 hat eigene Tests (verify_normalize_test.dart).
    audio = FakeAudioInput();
    engine = FakeWakeWordEngine(hitAtFrame: hits, acceptDelay: acceptDelay);
    verifier = FakeWakeVerifier();
    listener = WakeWordListener(
      audio: audio,
      engine: engine,
      verifier: v ?? verifier,
      verifyTail: tail,
    );
    found = [];
    listener.detections.listen(found.add);
  }

  Future<void> feed(int frames, {int startAt = 0}) async {
    for (var i = 0; i < frames; i++) {
      audio.push(counting((startAt + i) * 480));
      await Future<void>.delayed(Duration.zero);
    }
    await settle();
  }

  test('Treffer wird bestätigt: Pre-Roll = 300 ms vor dem Treffer + lückenlos '
      'alles danach, sample-genau', () async {
    setUpListener(hits: {19});
    final gate = verifier.gate = Completer<void>();
    await listener.start();
    await feed(20); // Treffer bei Frame 19 (Samples 9120..9599)
    expect(verifier.calls, hasLength(1)); // Prüfung läuft noch
    await feed(5, startAt: 20); // Frames kommen während der Prüfung
    expect(found, isEmpty);
    gate.complete();
    await settle();
    expect(found, hasLength(1));
    final pre = found.single.preRoll;
    // 300 ms = 4800 Samples vor dem Ende von Frame 19 (Sample 9600).
    expect(pre.first, 9600 - 4800);
    for (var i = 1; i < pre.length; i++) {
      expect(pre[i], pre[i - 1] + 1, reason: 'Lücke bei $i');
    }
    expect(pre.length, 4800 + 5 * 480);
    expect(pre.last, 9600 + 5 * 480 - 1);
    // WP68: the wake word ends 300 ms into the pre-roll, and the stream
    // position at its end is where the owner continues without a gap.
    expect(found.single.wakeEnd, 4800);
    expect(found.single.position, 9600 + 5 * 480);
    // Die Prüfung bekommt höchstens 2 s Audio, die letzten vor dem Treffer.
    expect(verifier.calls.single.length, 9600);
    expect(verifier.calls.single.last, 9599);
    expect(listener.stats.confirmed, 1);
    expect(listener.stats.candidates, 1);
    await listener.dispose();
  });

  test(
    'Nachlauf: Prüfung bekommt ~3 s, davon 0,9 s nach dem Treffer',
    () async {
      setUpListener(hits: {99}, tail: const Duration(milliseconds: 900));
      await listener.start();
      await feed(100); // Treffer bei Frame 99 (Ende Sample 48000)
      expect(verifier.calls, isEmpty); // wartet noch auf den Nachlauf
      await feed(40, startAt: 100);
      expect(verifier.calls, hasLength(1));
      final lead = verifier.calls.single;
      expect(lead.first, 48000 - 32000);
      expect(lead.length, 32000 + 14400);
      expect(lead.last, (48000 + 14400 - 1) % 30000); // Zähler läuft um
      expect(found, hasLength(1));
      expect(
        found.single.latency,
        greaterThanOrEqualTo(const Duration(milliseconds: 900)),
      );
      // Pre-Roll beginnt 300 ms vor dem Treffer und enthält den Nachlauf.
      expect(found.single.preRoll.first, (48000 - 4800) % 30000);
      await listener.dispose();
    },
  );

  test('Pause und Stop leeren Ring und Nachlauf-Sammlung', () async {
    setUpListener(hits: {10});
    verifier.gate = Completer<void>();
    await listener.start();
    await feed(15);
    expect(listener.bufferedSamples, greaterThan(0));
    await listener.pause();
    expect(listener.bufferedSamples, 0);
    await listener.resume();
    await feed(5);
    expect(listener.bufferedSamples, greaterThan(0));
    await listener.stop();
    expect(listener.bufferedSamples, 0);
    await listener.dispose();
  });

  test('Pre-Roll hängt am Treffer, nicht am Verarbeitungszeitpunkt '
      '(verzögerte Engine)', () async {
    setUpListener(hits: {19}, acceptDelay: const Duration(milliseconds: 3));
    await listener.start();
    // Audio läuft der Engine davon: bis zur Verarbeitung von Frame 19 sind
    // schon 40 Frames da.
    for (var i = 0; i < 40; i++) {
      audio.push(counting(i * 480));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(found, hasLength(1));
    final pre = found.single.preRoll;
    expect(pre.first, 9600 - 4800);
    for (var i = 1; i < pre.length; i++) {
      expect(pre[i], pre[i - 1] + 1, reason: 'Lücke bei $i');
    }
    expect(pre.last, 40 * 480 - 1);
    // Die Prüfung sieht nur Audio bis zum Treffer (+ Nachlauf 0).
    expect(verifier.calls.single.last, 9599);
    await listener.dispose();
  });

  test(
    'Nachprüfung lehnt ab: kein Trigger, Zähler nur bei Kandidaten',
    () async {
      setUpListener(hits: {3, 60});
      verifier.answer = (n) => n == 2;
      await listener.start();
      await feed(70);
      expect(listener.stats.candidates, 2);
      expect(listener.stats.confirmed, 1);
      expect(found, hasLength(1));
      expect(verifier.calls, hasLength(2));
      await listener.dispose();
    },
  );

  test('Verifier-Fehler oder -Timeout zählt als abgelehnt', () async {
    setUpListener(hits: {3});
    verifier.error = StateError('Whisper weg');
    await listener.start();
    await feed(10);
    expect(found, isEmpty);
    expect(listener.state, WakeListenerState.listening);
    await listener.dispose();

    setUpListener(hits: {3});
    listener = WakeWordListener(
      audio: audio,
      engine: engine,
      verifier: FakeWakeVerifier(delay: const Duration(seconds: 5)),
      verifyTimeout: const Duration(milliseconds: 10),
    );
    found = [];
    listener.detections.listen(found.add);
    await listener.start();
    await feed(10);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(found, isEmpty);
    expect(listener.stats.candidates, 1);
    await listener.dispose();
  });

  test(
    'Sperrzeit: Doppeltreffer innerhalb 1,5 s zählen nicht, danach wieder',
    () async {
      // Frames à 30 ms: 10, 20 (300 ms später) und 80 (2,1 s später).
      setUpListener(hits: {10, 20, 80});
      await listener.start();
      await feed(90);
      expect(found, hasLength(2));
      expect(listener.stats.candidates, 2);
      await listener.dispose();
    },
  );

  test('ohne Verifier gilt jeder Kandidat', () async {
    audio = FakeAudioInput();
    engine = FakeWakeWordEngine(hitAtFrame: {2});
    listener = WakeWordListener(audio: audio, engine: engine);
    found = [];
    listener.detections.listen(found.add);
    await listener.start();
    await feed(5);
    expect(found, hasLength(1));
    await listener.dispose();
  });

  test('Pause und Fortsetzen geben das AudioInput frei', () async {
    setUpListener(hits: {2});
    await listener.start();
    expect(audio.isRunning, isTrue);
    await listener.pause();
    expect(audio.isRunning, isFalse);
    expect(listener.state, WakeListenerState.paused);
    await listener.resume();
    expect(audio.isRunning, isTrue);
    expect(audio.startCount, 2);
    expect(listener.state, WakeListenerState.listening);
    await feed(5); // Positionen beginnen wieder bei 0
    expect(found, hasLength(1));
    await listener.stop();
    expect(audio.isRunning, isFalse);
    expect(engine.isOpen, isFalse);
    expect(listener.state, WakeListenerState.idle);
    await listener.pause(); // no-op
    await listener.resume(); // no-op
    await listener.dispose();
  });

  test('Fehler im Audio-Strom beendet den Listener mit Grundcode', () async {
    setUpListener();
    await listener.start();
    final states = <WakeListenerState>[];
    listener.states.listen(states.add);
    audio.fail(
      const VoiceException(VoiceErrorKind.unavailable, 'Mikrofon weg'),
    );
    await settle();
    expect(listener.state, WakeListenerState.failed);
    expect(listener.failure?.kind, VoiceErrorKind.unavailable);
    expect(audio.isRunning, isFalse);
    expect(engine.isOpen, isFalse);
    expect(states, [WakeListenerState.failed]);
    await listener.dispose();
  });

  test(
    'unbekannter Fehler, Engine-Fehler und endender Strom -> failed',
    () async {
      setUpListener();
      await listener.start();
      audio.fail(StateError('kaputt'));
      await settle();
      expect(listener.failure?.kind, VoiceErrorKind.failed);
      await listener.dispose();

      setUpListener();
      engine.acceptError = StateError('ONNX');
      await listener.start();
      await feed(1);
      expect(listener.state, WakeListenerState.failed);
      expect(listener.failure?.cause, isA<StateError>());
      await listener.dispose();

      audio = FakeAudioInput(closeAfterFrames: true);
      engine = FakeWakeWordEngine();
      listener = WakeWordListener(audio: audio, engine: engine);
      await listener.start();
      await settle();
      expect(listener.state, WakeListenerState.failed);
      expect(listener.failure?.kind, VoiceErrorKind.unavailable);
      await listener.dispose();
    },
  );

  test('start ohne Berechtigung: failed und Fehler weitergereicht', () async {
    audio = FakeAudioInput(
      startError: const VoiceException(
        VoiceErrorKind.permissionDenied,
        'Mikrofon verweigert',
      ),
    );
    engine = FakeWakeWordEngine();
    listener = WakeWordListener(audio: audio, engine: engine);
    await expectLater(
      listener.start(),
      throwsA(
        isA<VoiceException>().having(
          (e) => e.kind,
          'kind',
          VoiceErrorKind.permissionDenied,
        ),
      ),
    );
    expect(listener.state, WakeListenerState.failed);
    expect(engine.isOpen, isFalse);
    await listener.dispose();
  });

  test('Kennzahlen: Kandidaten/h und bestätigt/h aus der Laufzeit', () {
    const s = WakeWordStats(
      candidates: 6,
      confirmed: 1,
      runtime: Duration(hours: 2),
    );
    expect(s.candidatesPerHour, 3);
    expect(s.confirmedPerHour, 0.5);
    const short = WakeWordStats(
      candidates: 1,
      confirmed: 1,
      runtime: Duration(seconds: 30),
    );
    expect(short.candidatesPerHour, 0);
    expect(s.toString(), contains('candidates 6'));
  });

  test('WakeWordTrigger meldet TriggerKind.wakeWord mit Pre-Roll', () async {
    setUpListener(hits: {5});
    final trigger = WakeWordTrigger(
      listener,
      FixedClock(DateTime.utc(2026, 10, 14)),
    );
    final events = <TriggerEvent>[];
    trigger.triggers.listen(events.add);
    await listener.start();
    await feed(8);
    expect(events, hasLength(1));
    expect(events.single.source, TriggerKind.wakeWord);
    expect(events.single.at, DateTime.utc(2026, 10, 14));
    expect(events.single.preRoll, isNotEmpty);
    await listener.dispose();
  });
}
