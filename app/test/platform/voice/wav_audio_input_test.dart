import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/wav_audio_input.dart';

void main() {
  test('verpasste Ticks: die nach Uhr fälligen Frames kommen nach', () {
    fakeAsync((async) {
      // The clock runs on its own: a late timer tick (load) sees more time
      // passed than one interval.
      var t = DateTime(2026);
      withClock(Clock(() => t), () {
        final input = WavAudioInput(
          Int16List(16000),
          leadingSilence: Duration.zero,
        );
        var frames = 0;
        final sub = input.start().listen((_) => frames++);
        t = t.add(const Duration(milliseconds: 20));
        async.elapse(const Duration(milliseconds: 20));
        expect(frames, 1);
        // 200 ms pass, but the timer fires once only.
        t = t.add(const Duration(milliseconds: 200));
        async.elapse(const Duration(milliseconds: 20));
        expect(frames, 11, reason: '220 ms = 11 Frames à 20 ms');
        sub.cancel();
        input.stop();
      });
    });
  });

  test('pünktliche Ticks: genau ein Frame je Tick', () {
    fakeAsync((async) {
      var t = DateTime(2026);
      withClock(Clock(() => t), () {
        final input = WavAudioInput(
          Int16List(16000),
          leadingSilence: Duration.zero,
        );
        var frames = 0;
        final sub = input.start().listen((_) => frames++);
        for (var i = 0; i < 5; i++) {
          t = t.add(const Duration(milliseconds: 20));
          async.elapse(const Duration(milliseconds: 20));
        }
        expect(frames, 5);
        sub.cancel();
        input.stop();
      });
    });
  });

  test('nach langer Pause kein Burst: höchstens maxCatchUpFrames je Tick', () {
    fakeAsync((async) {
      var t = DateTime(2026);
      withClock(Clock(() => t), () {
        final input = WavAudioInput(
          Int16List(16000 * 20),
          leadingSilence: Duration.zero,
        );
        var frames = 0;
        final sub = input.start().listen((_) => frames++);
        // 10 s Pause (Suspend), der Timer feuert einmal.
        t = t.add(const Duration(seconds: 10));
        async.elapse(const Duration(milliseconds: 20));
        expect(frames, WavAudioInput.maxCatchUpFrames);
        // Danach wieder im Takt: ein Frame je Tick, kein Rückstau.
        t = t.add(const Duration(milliseconds: 20));
        async.elapse(const Duration(milliseconds: 20));
        expect(frames, WavAudioInput.maxCatchUpFrames + 1);
        sub.cancel();
        input.stop();
      });
    });
  });
}
