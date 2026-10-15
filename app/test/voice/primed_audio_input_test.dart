// B11 / privacy (WP30 review): the early recording keeps frames only until
// the pipeline takes them; a stop drops everything buffered.

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/primed_audio_input.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  test('zweiter Start während der Aufnahme: VoiceException busy', () async {
    final inner = FakeAudioInput(
      frames: AudioFrames.pattern('S' * 5),
      frameInterval: const Duration(milliseconds: 1),
    );
    final primed = PrimedAudioInput(inner)..prime();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final sub = primed.start().listen((_) {});
    expect(
      primed.start,
      throwsA(
        isA<VoiceException>().having(
          (e) => e.kind,
          'kind',
          VoiceErrorKind.busy,
        ),
      ),
    );
    await sub.cancel();
    await primed.stop();
  });

  test('stop leert den Puffer, der nächste Start ist live', () async {
    final inner = FakeAudioInput(
      frames: AudioFrames.pattern('S' * 5),
      frameInterval: const Duration(milliseconds: 1),
    );
    final primed = PrimedAudioInput(inner)..prime();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(primed.isPrimed, isTrue);
    expect(primed.buffered, greaterThan(Duration.zero));

    await primed.stop();
    expect(primed.buffered, Duration.zero);
    expect(primed.isPrimed, isFalse);
    expect(primed.isRunning, isFalse);
    expect(inner.isRunning, isFalse);

    // Not primed again: start goes straight to the microphone and gets
    // only its new frames, nothing of the stopped recording.
    inner.script(AudioFrames.pattern('.' * 2));
    final frames = await primed.start().take(2).toList();
    expect(frames, hasLength(2));
    expect(frames.every((f) => f.every((s) => s == 0)), isTrue);
    expect(inner.startCount, 2);
    await primed.stop();
  });

  test('ohne stop: der Puffer kommt beim Start zuerst', () async {
    final inner = FakeAudioInput(frames: AudioFrames.pattern('SS'));
    final primed = PrimedAudioInput(inner)..prime();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final frames = await primed.start().take(2).toList();
    expect(frames.every((f) => f.any((s) => s != 0)), isTrue);
    expect(primed.buffered, Duration.zero);
    await primed.stop();
  });
}
