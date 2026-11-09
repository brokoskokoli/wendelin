// WP188 C1: AudioTrackPlayback gegen einen Fake-Kanal: Ende-Meldung erst mit
// der Antwort des Kanals, Stopp, Ersetzen, Sicherheits-Timeout, Fehlerpfade.
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/channels.dart';
import 'package:wendelin/platform/voice/audio_track_playback.dart';
import 'package:wendelin/platform/voice/pcm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(audioPlaybackChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final wav = Wav(Int16List(16000)); // 1 s

  late List<MethodCall> calls;
  late List<Completer<void>> plays;
  Object? playError;

  setUp(() {
    calls = [];
    plays = [];
    playError = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'play') {
        if (playError != null) throw playError!;
        final c = Completer<void>();
        plays.add(c);
        await c.future;
      } else if (call.method == 'stop') {
        for (final c in plays) {
          if (!c.isCompleted) c.complete();
        }
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  int count(String m) => calls.where((c) => c.method == m).length;

  test('sends PCM and rate; completes when the channel answers', () async {
    var finished = false;
    final f = AudioTrackPlayback().play(wav).then((_) => finished = true);
    await pumpEventQueue();
    expect(count('play'), 1);
    final args = calls.first.arguments as Map;
    expect((args['pcm'] as Uint8List).length, 32000);
    expect(args['sampleRate'], 16000);
    expect(finished, isFalse, reason: 'not before the native end');
    plays.single.complete();
    await f;
    expect(finished, isTrue);
  });

  test(
    'stop during the await ends the play and tells the native side',
    () async {
      final p = AudioTrackPlayback();
      var finished = false;
      final f = p.play(wav).then((_) => finished = true);
      await pumpEventQueue();
      await p.stop();
      await f;
      expect(finished, isTrue);
      expect(count('stop'), 1);
    },
  );

  test('stop without a running play does nothing', () async {
    await AudioTrackPlayback().stop();
    expect(calls, isEmpty);
  });

  test('a newer play ends the older one without a stop', () async {
    final p = AudioTrackPlayback();
    var first = false;
    final a = p.play(wav).then((_) => first = true);
    await pumpEventQueue();
    final b = p.play(wav);
    // Far below the 6 s safety limit: only the newer play can have ended it.
    await a.timeout(const Duration(seconds: 1));
    expect(first, isTrue);
    expect(count('stop'), 0, reason: 'native replaces the clip itself');
    plays.last.complete();
    await b;
  });

  test('safety timeout ends the play and stops the native side', () {
    fakeAsync((async) {
      var finished = false;
      unawaited(AudioTrackPlayback().play(wav).then((_) => finished = true));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5, milliseconds: 900));
      expect(finished, isFalse);
      async.elapse(const Duration(milliseconds: 200));
      expect(finished, isTrue);
      expect(count('stop'), 1);
    });
  });

  test('missing plugin is AudioTrackUnavailable', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      AudioTrackPlayback().play(wav),
      throwsA(isA<AudioTrackUnavailable>()),
    );
  });

  test('a native error is AudioTrackUnavailable', () async {
    playError = PlatformException(code: 'failed');
    await expectLater(
      AudioTrackPlayback().play(wav),
      throwsA(isA<AudioTrackUnavailable>()),
    );
  });
}
