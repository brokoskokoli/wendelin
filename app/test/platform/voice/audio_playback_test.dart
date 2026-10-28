// WP165: Wiedergabe über audioplayers: Kontext (Assistent, normaler Modus),
// Stopp-Rennen (Stopp während des Kontextwechsels bzw. Stoppens des Vorgängers).
import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/audio_playback.dart';
import 'package:wendelin/platform/voice/pcm.dart';

final class _Player implements AudioPlayer {
  final contexts = <AudioContext>[];
  final complete = StreamController<void>.broadcast();

  /// Holds `setAudioContext` (the context is recorded when it is released).
  Completer<void>? contextGate;
  var plays = 0;
  var stops = 0;

  /// Holds `stop` (the stop is counted when it is released).
  Completer<void>? stopGate;

  @override
  Stream<void> get onPlayerComplete => complete.stream;

  @override
  Future<void> setAudioContext(AudioContext ctx) async {
    await contextGate?.future;
    contexts.add(ctx);
  }

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async => plays++;

  @override
  Future<void> stop() async {
    await stopGate?.future;
    stops++;
  }

  Future<void> close() => complete.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('AudioplayersPlayback', () {
    Future<void> playOnce(AudioplayersPlayback p, _Player player) async {
      final done = p.play(Wav(Int16List(160)));
      await Future<void>.delayed(Duration.zero);
      player.complete.add(null);
      await done;
    }

    test('Stopp vor dem ersten Play: der Player startet nicht mehr', () async {
      final player = _Player()..contextGate = Completer<void>();
      addTearDown(player.close);
      final p = AudioplayersPlayback(player);
      final done = p.play(Wav(Int16List(160)));
      await Future<void>.delayed(Duration.zero);
      await p.stop(); // while setAudioContext is still running
      player.contextGate!.complete();
      await done; // returns at once, no wait for the safety limit
      expect(player.plays, 0);
      expect(player.stops, greaterThan(0));
    });

    test(
      'neues Play während des Kontextwechsels: das alte startet nicht',
      () async {
        final player = _Player()..contextGate = Completer<void>();
        addTearDown(player.close);
        final p = AudioplayersPlayback(player);
        final first = p.play(Wav(Int16List(160)));
        await Future<void>.delayed(Duration.zero);
        final second = p.play(Wav(Int16List(160)));
        await Future<void>.delayed(Duration.zero);
        player.contextGate!.complete();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(player.plays, 1); // only the newer one
        player.complete.add(null);
        await Future.wait([first, second]);
      },
    );

    test('neues Play verdrängt das laufende: das alte kehrt sofort zurück, '
        'ohne Sicherheits-Timeout', () {
      fakeAsync((async) {
        final player = _Player();
        final p = AudioplayersPlayback(player);
        var firstDone = false;
        var secondDone = false;
        unawaited(p.play(Wav(Int16List(160))).then((_) => firstDone = true));
        async.flushMicrotasks();
        expect(player.plays, 1);
        unawaited(p.play(Wav(Int16List(160))).then((_) => secondDone = true));
        async.flushMicrotasks(); // no time elapsed: no safety timeout
        expect(firstDone, isTrue);
        expect(secondDone, isFalse);
        expect(player.plays, 2);
        player.complete.add(null);
        async.flushMicrotasks();
        expect(secondDone, isTrue);
        unawaited(player.close());
      });
    });

    test('Stopp, während play() auf das Stoppen des vorigen Plays wartet: '
        'das neue Play startet nicht', () async {
      final player = _Player();
      addTearDown(player.close);
      final p = AudioplayersPlayback(player);
      final first = p.play(Wav(Int16List(160)));
      await Future<void>.delayed(Duration.zero);
      expect(player.plays, 1); // the first one is still running
      player.stopGate = Completer<void>();
      final second = p.play(Wav(Int16List(160))); // waits for the stop of first
      await Future<void>.delayed(Duration.zero);
      unawaited(p.stop()); // in the window before the new play is set
      await Future<void>.delayed(Duration.zero);
      player.stopGate!.complete();
      await Future.wait([first, second]);
      expect(player.plays, 1); // the second one must not start
    });

    test('Kontext: Assistent, Modus normal, nur einmal gesetzt', () async {
      final player = _Player();
      addTearDown(player.close);
      final p = AudioplayersPlayback(player);
      await playOnce(p, player);
      await playOnce(p, player);
      expect(player.contexts, [AudioplayersPlayback.context]);
      expect(
        AudioplayersPlayback.context.android.usageType,
        AndroidUsageType.assistant,
      );
      // Unchanged: audioplayers sets MODE_NORMAL on a context change.
      expect(
        AudioplayersPlayback.context.android.audioMode,
        AndroidAudioMode.normal,
      );
    });
  });
}
