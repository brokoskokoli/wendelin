// WP146: the service keeps recording until the first frame of the app's
// microphone; the tail is joined to the pre-roll without a hole or doubled
// audio.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/wake_pre_roll.dart';

import '../../overlay/assistant_overlay_test.dart' show FakeAssistantPlatform;

Int16List filled(int value, int n) => Int16List(n)..fillRange(0, n, value);

void main() {
  final lines = <String>[];
  late void Function(String) saved;
  setUp(() {
    lines.clear();
    saved = voiceLogSink;
    voiceLogSink = lines.add;
  });
  tearDown(() => voiceLogSink = saved);

  WakePreRoll pre({int mute = 0}) =>
      WakePreRoll(pcm: filled(1, 1600), wakeEnd: 800, muteMicSamples: mute);

  test(
    'Überlappung (negative Lücke): das doppelte Ende des Reste wird gekürzt',
    () {
      // Tail 100 ms, its last sample at t=1000; the app's first frame (100 ms)
      // arrives at 1060, so it began at 960: 40 ms are doubled.
      final out = bridgeWakeTail(
        pre(),
        (pcm: filled(5, 1600), lastSampleAtMs: 1000),
        firstFrameAtMs: 1060,
        firstFrameSamples: 1600,
        afterTakeMs: 300,
      );
      expect(out.pcm, hasLength(1600 + 1600 - 40 * 16));
      expect(out.pcm.sublist(0, 1600).every((s) => s == 1), isTrue);
      expect(out.pcm.sublist(1600).every((s) => s == 5), isTrue);
      expect(lines.single, contains('ms=-40'));
      expect(lines.single, contains('trim=40'));
      expect(lines.single, contains('silence=0'));
    },
  );

  test('Lücke (positive): als Stille eingefügt, nicht verklebt', () {
    final out = bridgeWakeTail(
      pre(),
      (pcm: filled(5, 1600), lastSampleAtMs: 1000),
      firstFrameAtMs: 1130,
      firstFrameSamples: 0,
    );
    expect(out.pcm, hasLength(1600 + 1600 + 130 * 16));
    expect(out.pcm.sublist(3200).every((s) => s == 0), isTrue);
    expect(lines.single, contains('ms=130'));
    expect(lines.single, contains('silence=130'));
  });

  test('Stille höchstens wakeHoleMax', () {
    final out = bridgeWakeTail(
      pre(),
      (pcm: filled(5, 1600), lastSampleAtMs: 1000),
      firstFrameAtMs: 9000,
      firstFrameSamples: 0,
    );
    expect(out.pcm, hasLength(3200 + wakeHoleMax.inMilliseconds * 16));
    expect(lines.single, contains('silence=${wakeHoleMax.inMilliseconds}'));
  });

  test(
    'Bestätigungston: Anfang des Rests stumm, Rest-Stummschaltung kürzer',
    () {
      final out = bridgeWakeTail(
        pre(mute: 6400),
        (pcm: filled(5, 1600), lastSampleAtMs: 1000),
        firstFrameAtMs: 1100,
        firstFrameSamples: 0,
      );
      // All 1600 tail samples are within the tone: silenced. Together with the
      // 100 ms hole (silence) 3200 samples of the tone are covered.
      expect(out.pcm.sublist(1600).every((s) => s == 0), isTrue);
      expect(out.muteMicSamples, 6400 - 3200);
      final partial = bridgeWakeTail(
        pre(mute: 800),
        (pcm: filled(5, 1600), lastSampleAtMs: 1000),
        firstFrameAtMs: 1100,
        firstFrameSamples: 0,
      );
      expect(partial.pcm.sublist(1600, 2400).every((s) => s == 0), isTrue);
      expect(partial.pcm.sublist(2400, 3200).every((s) => s == 5), isTrue);
      expect(partial.muteMicSamples, 0);
    },
  );

  test('ohne Zeitangaben: Rest unverändert angehängt, Wake-Ende bleibt', () {
    final out = bridgeWakeTail(pre(), (
      pcm: filled(5, 100),
      lastSampleAtMs: null,
    ));
    expect(out.pcm, hasLength(1700));
    expect(out.wakeEnd, 800);
    expect(out.lastSampleAtMs, isNull);
    expect(lines.single, isNot(contains('ms=')));
  });

  test('Log: nur Zahlen und Codes (Privacy-Positivliste)', () {
    bridgeWakeTail(
      pre(),
      (pcm: filled(5, 1600), lastSampleAtMs: 1000),
      firstFrameAtMs: 1060,
      firstFrameSamples: 1600,
      afterTakeMs: 300,
    );
    expect(
      lines.single,
      matches(
        RegExp(r'^Wendelin/voice: wake-gap engine=app( \w+=(-?\d+|overlap))+$'),
      ),
    );
  });

  test(
    'takeWakePreRoll: Dienst bleibt offen, finish einmal und mit dem Rest',
    () async {
      final platform = FakeAssistantPlatform()
        ..wakeHandoff = filled(2, 3200)
        ..wakeEnd = 1600
        ..finishAudio = WakeHandoffAudio(
          pcm: filled(4, 800),
          wakeEnd: 0,
          capturedMs: 50,
          lastSampleAtMs: 1234,
        );
      final pre = await takeWakePreRoll(
        platform: platform,
        tone: false,
        playTone: () async {},
      );
      expect(platform.wakeKeptOpen, 1);
      expect(platform.wakeFinishes, 0, reason: 'erst beim ersten Frame');
      final a = await pre!.finish!();
      final b = await pre.finish!();
      expect(platform.wakeFinishes, 1, reason: 'einmal');
      expect(a!.pcm, hasLength(800));
      expect(a.lastSampleAtMs, 1234);
      expect(identical(a, b), isTrue);
    },
  );
}
