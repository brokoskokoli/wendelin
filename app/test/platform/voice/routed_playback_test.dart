// WP188 C1: Weiche je play: System (nichts gespeichert) bleibt auf dem
// bisherigen Weg ohne zusätzliches await, Wahl gesetzt geht auf AudioTrack,
// Ausfall des nativen Wegs fällt auf System zurück, Stopp-Rennen.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/audio_track_playback.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/routed_playback.dart';
import 'package:wendelin/platform/voice/sherpa_tts.dart';

final class _Fake implements AudioPlayback {
  var plays = 0;
  var stops = 0;
  Object? error;
  Completer<void>? stopGate;
  Completer<void>? playGate;

  @override
  Future<void> play(Wav wav) async {
    plays++;
    if (error != null) throw error!;
    await playGate?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopGate?.future;
    if (playGate?.isCompleted == false) playGate?.complete();
  }
}

void main() {
  final wav = Wav(Int16List.fromList([1, 2, 3]));
  late _Fake system;
  late _Fake track;
  var chosen = false;
  late RoutedPlayback router;

  setUp(() {
    system = _Fake();
    track = _Fake();
    chosen = false;
    router = RoutedPlayback(
      system: system,
      track: track,
      hasChoice: () => chosen,
    );
  });

  test('no choice: system path, track untouched', () async {
    await router.play(wav);
    expect((system.plays, track.plays), (1, 0));
  });

  test('no choice: the system play starts synchronously', () {
    unawaited(router.play(wav));
    expect(system.plays, 1, reason: 'no await before the old path');
  });

  test('choice set: track path', () async {
    chosen = true;
    await router.play(wav);
    expect((system.plays, track.plays), (0, 1));
  });

  test('unreadable choice is system', () async {
    router = RoutedPlayback(
      system: system,
      track: track,
      hasChoice: () => throw StateError('x'),
    );
    await router.play(wav);
    expect((system.plays, track.plays), (1, 0));
  });

  test('track unavailable: the clip plays on system', () async {
    chosen = true;
    track.error = const AudioTrackUnavailable('x');
    await router.play(wav);
    expect((system.plays, track.plays), (1, 1));
  });

  test('other errors are not swallowed', () async {
    chosen = true;
    track.error = StateError('x');
    await expectLater(router.play(wav), throwsStateError);
    expect(system.plays, 0);
  });

  test('stop during a failing track play: no fallback afterwards', () async {
    chosen = true;
    track.playGate = Completer<void>();
    final f = router.play(wav);
    await pumpEventQueue();
    track.error = const AudioTrackUnavailable('x');
    await router.stop();
    await f;
    expect(system.plays, 0);
  });

  test('choice changed: next play stops the old path first', () async {
    system.playGate = Completer<void>();
    final a = router.play(wav);
    await pumpEventQueue();
    chosen = true;
    await router.play(wav);
    await a;
    expect(system.stops, 1);
    expect(track.plays, 1);
  });

  test(
    'stop during the stop of the old path: new play does not start',
    () async {
      system.playGate = Completer<void>();
      unawaited(router.play(wav));
      await pumpEventQueue();
      chosen = true;
      system.stopGate = Completer<void>();
      final b = router.play(wav);
      await pumpEventQueue();
      final s = router.stop();
      system.stopGate!.complete();
      await b;
      await s;
      expect(track.plays, 0);
    },
  );

  test('stop stops the active path only', () async {
    chosen = true;
    track.playGate = Completer<void>();
    unawaited(router.play(wav));
    await pumpEventQueue();
    await router.stop();
    expect((system.stops, track.stops), (0, 1));
  });
}
