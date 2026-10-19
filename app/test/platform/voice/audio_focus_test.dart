// WP90: Ducking statt Pausieren - Fokus für die ganze Antwort und die Aufnahme.
import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/platform/channel_audio_focus_port.dart';
import 'package:wendelin/platform/voice/audio_playback.dart';
import 'package:wendelin/platform/voice/ducking_tts.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/record_audio_input.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

final class _FakeFocus implements AudioFocusPort {
  final log = <String>[];
  // Lives as long as the test.
  // ignore: close_sinks
  final _changes = StreamController<AudioFocusChange>.broadcast(sync: true);

  void emit(AudioFocusKind kind, {required bool lost}) =>
      _changes.add(AudioFocusChange(kind, lost: lost));

  @override
  Stream<AudioFocusChange> get changes => _changes.stream;

  @override
  Future<bool> acquire(AudioFocusKind kind) async {
    log.add('+${kind.name}');
    return true;
  }

  @override
  Future<void> release(AudioFocusKind kind) async => log.add('-${kind.name}');
}

final class _Recorder implements AudioRecorder {
  bool fail = false;
  final calls = <String>[];

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    if (fail) throw StateError('x');
    return const Stream<Uint8List>.empty();
  }

  @override
  Stream<RecordState> onStateChanged() => const Stream<RecordState>.empty();

  @override
  Future<String?> stop() async {
    calls.add('stop');
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubTts implements TextToSpeech {
  @override
  TtsState get state => TtsState.idle;

  @override
  Stream<TtsState> get states => const Stream<TtsState>.empty();

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<List<TtsVoice>> voices() async => const [];

  @override
  Future<void> speak(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  }) async {}

  @override
  Future<void> stop() async {}
}

final class _ThrowingTts extends _StubTts {
  @override
  Future<void> speak(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  }) async => throw StateError('engine');
}

final class _HangingTts extends _StubTts {
  final _done = Completer<void>();
  void finish() => _done.complete();

  @override
  Future<void> speak(
    String text, {
    String? voice,
    String? language,
    double rate = 1.0,
  }) => _done.future;
}

final class _FakeAudioPlayer implements AudioPlayer {
  final calls = <String>[];
  // ignore: close_sinks
  final complete = StreamController<void>.broadcast();
  AudioContext? context;

  @override
  Stream<void> get onPlayerComplete => complete.stream;

  @override
  Future<void> setAudioContext(AudioContext ctx) async {
    context = ctx;
    calls.add('context');
  }

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async => calls.add('play');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('SpeechFocus (ganze Antwort)', () {
    test('ein Fokus für mehrere Sätze, Abgabe erst nach der Haltezeit', () {
      fakeAsync((async) {
        final port = _FakeFocus();
        final focus = SpeechFocus(port);
        focus.begin();
        async.flushMicrotasks();
        focus.end(focus.generation);
        async.elapse(const Duration(milliseconds: 500));
        focus.begin(); // next sentence
        async.flushMicrotasks();
        focus.end(focus.generation);
        async.elapse(const Duration(milliseconds: 1499));
        expect(port.log, isNot(contains('-duck')));
        async.elapse(const Duration(milliseconds: 2));
        expect(port.log.last, '-duck');
        expect(port.log.where((e) => e == '-duck'), hasLength(1));
      });
    });

    test('Pipeline arbeitet noch (Tool-Runde): Fokus bleibt über die Haltezeit '
        'hinaus, danach Nachlauf', () {
      fakeAsync((async) {
        final port = _FakeFocus();
        final focus = SpeechFocus(port)..busy = true;
        focus.begin();
        async.flushMicrotasks();
        focus.end(focus.generation);
        async.elapse(const Duration(seconds: 30)); // slow tool round
        expect(port.log, ['+duck']);
        focus.begin(); // next sentence after the round
        async.flushMicrotasks();
        focus.end(focus.generation);
        focus.busy = false; // pipeline idle
        async.elapse(const Duration(milliseconds: 1499));
        expect(port.log, isNot(contains('-duck')));
        async.elapse(const Duration(milliseconds: 2));
        expect(port.log.last, '-duck');
      });
    });

    test('busy nach end(): bereits geplante Abgabe entfällt', () {
      fakeAsync((async) {
        final port = _FakeFocus();
        final focus = SpeechFocus(port);
        focus.begin();
        async.flushMicrotasks();
        focus.end(focus.generation); // hold timer runs
        async.elapse(const Duration(milliseconds: 500));
        focus.busy = true; // the pipeline thinks on (tool round)
        async.elapse(const Duration(seconds: 30));
        expect(port.log, ['+duck']);
      });
    });

    test('Fokus nach Android-Entzug: nächster Satz fordert neu an', () {
      fakeAsync((async) {
        final port = _FakeFocus();
        final focus = SpeechFocus(port);
        focus.begin();
        async.flushMicrotasks();
        focus.end(focus.generation);
        focus.begin();
        async.flushMicrotasks();
        expect(port.log, ['+duck', '+duck']);
      });
    });

    test(
      'end() einer abgebrochenen Antwort zählt die nächste nicht herunter',
      () {
        fakeAsync((async) {
          final port = _FakeFocus();
          final focus = SpeechFocus(port);
          final old = focus.generation;
          focus.begin();
          async.flushMicrotasks();
          focus.drop(); // stop
          final fresh = focus.generation;
          focus.begin(); // next answer
          async.flushMicrotasks();
          focus.end(old); // late end of the stopped sentence
          async.elapse(const Duration(seconds: 5));
          expect(port.log.last, '+duck'); // still held
          focus.end(fresh);
          async.elapse(const Duration(seconds: 2));
          expect(port.log.last, '-duck');
        });
      },
    );

    test('stop gibt den Fokus sofort ab', () {
      fakeAsync((async) {
        final port = _FakeFocus();
        final focus = SpeechFocus(port);
        focus.begin();
        async.flushMicrotasks();
        focus.drop();
        async.flushMicrotasks();
        expect(port.log, ['+duck', '-duck']);
        async.elapse(const Duration(seconds: 5));
        expect(port.log, hasLength(2));
      });
    });
  });

  test('DuckingTextToSpeech: Fokus während des Sprechens', () {
    fakeAsync((async) {
      final port = _FakeFocus();
      final inner = _StubTts();
      final tts = DuckingTextToSpeech(inner, SpeechFocus(port));
      unawaited(tts.speak('Hallo'));
      async.flushMicrotasks();
      expect(port.log, ['+duck']);
      async.elapse(const Duration(seconds: 10));
      expect(port.log, ['+duck', '-duck']);
      unawaited(tts.speak('  ')); // nothing to say: no focus
      async.flushMicrotasks();
      expect(port.log, hasLength(2));
    });
  });

  test(
    'DuckingTextToSpeech: auch bei werfender Engine wird der Fokus frei',
    () {
      fakeAsync((async) {
        final port = _FakeFocus();
        final tts = DuckingTextToSpeech(_ThrowingTts(), SpeechFocus(port));
        Object? error;
        tts.speak('Hallo').catchError((Object e) => error = e);
        async.flushMicrotasks();
        expect(error, isA<StateError>());
        async.elapse(const Duration(seconds: 3));
        expect(port.log, ['+duck', '-duck']);
      });
    },
  );

  test('DuckingTextToSpeech: stop() während speak gibt sofort ab', () {
    fakeAsync((async) {
      final port = _FakeFocus();
      final inner = _HangingTts();
      final tts = DuckingTextToSpeech(inner, SpeechFocus(port));
      unawaited(tts.speak('Hallo'));
      async.flushMicrotasks();
      expect(port.log, ['+duck']);
      unawaited(tts.stop());
      async.flushMicrotasks();
      expect(port.log, ['+duck', '-duck']); // at once, no hold time
      inner.finish();
      async.elapse(const Duration(seconds: 5));
      expect(port.log, hasLength(2));
    });
  });

  group('Aufnahme', () {
    test('Erkennung hält den transienten Fokus bis zum Stopp', () async {
      final port = _FakeFocus();
      final rec = RecordPcmRecorder(_Recorder(), null, port);
      await rec.startStream();
      expect(port.log, ['+listen']);
      await rec.stop();
      expect(port.log, ['+listen', '-listen']);
    });

    test('Mithören während der Antwort nimmt keinen eigenen Fokus', () async {
      final port = _FakeFocus();
      final rec = RecordPcmRecorder(_Recorder(), null, port);
      await rec.startStream(CaptureProfile.speechOutput);
      await rec.stop();
      expect(port.log, isEmpty);
    });

    test(
      'Fokusverlust pausiert die Aufnahme, Rückgabe setzt sie fort',
      () async {
        final port = _FakeFocus();
        final plugin = _Recorder();
        final rec = RecordPcmRecorder(plugin, null, port);
        await rec.startStream();
        port.emit(AudioFocusKind.listen, lost: true);
        port.emit(AudioFocusKind.listen, lost: true); // repeated: once
        await Future<void>.delayed(Duration.zero);
        expect(plugin.calls, ['pause']);
        port.emit(AudioFocusKind.duck, lost: false); // other kind: ignored
        port.emit(AudioFocusKind.listen, lost: false);
        await Future<void>.delayed(Duration.zero);
        expect(plugin.calls, ['pause', 'resume']);
        await rec.stop();
        port.emit(AudioFocusKind.listen, lost: true); // after stop: ignored
        await Future<void>.delayed(Duration.zero);
        expect(plugin.calls, ['pause', 'resume', 'stop']);
      },
    );

    test('Verlust, Stopp, neue Sitzung, Verlust: pausiert wieder', () async {
      final port = _FakeFocus();
      final plugin = _Recorder();
      final rec = RecordPcmRecorder(plugin, null, port);
      await rec.startStream();
      port.emit(AudioFocusKind.listen, lost: true);
      await Future<void>.delayed(Duration.zero);
      await rec.stop(); // ended while paused
      await rec.startStream();
      port.emit(AudioFocusKind.listen, lost: true);
      await Future<void>.delayed(Duration.zero);
      expect(plugin.calls, ['pause', 'stop', 'pause']);
    });

    test('Verlust des Ducking-Fokus pausiert die Aufnahme nicht', () async {
      final port = _FakeFocus();
      final plugin = _Recorder();
      final rec = RecordPcmRecorder(plugin, null, port);
      await rec.startStream();
      port.emit(AudioFocusKind.duck, lost: true);
      await Future<void>.delayed(Duration.zero);
      expect(plugin.calls, isEmpty);
    });

    test(
      'Mithören während der Antwort pausiert nicht bei Fokuswechsel',
      () async {
        final port = _FakeFocus();
        final plugin = _Recorder();
        final rec = RecordPcmRecorder(plugin, null, port);
        await rec.startStream(CaptureProfile.speechOutput);
        port.emit(AudioFocusKind.listen, lost: true);
        await Future<void>.delayed(Duration.zero);
        expect(plugin.calls, isEmpty);
      },
    );

    test('Startfehler gibt den Fokus wieder ab', () async {
      final port = _FakeFocus();
      final rec = RecordPcmRecorder(_Recorder()..fail = true, null, port);
      await expectLater(rec.startStream(), throwsStateError);
      expect(port.log, ['+listen', '-listen']);
    });
  });

  test('Sherpa-Wiedergabe fordert nur transienten Fokus mit Ducking', () {
    final a = AudioplayersPlayback.context.android;
    expect(a.audioFocus, AndroidAudioFocus.gainTransientMayDuck);
    expect(a.usageType, AndroidUsageType.assistant);
    expect(a.contentType, AndroidContentType.speech);
  });

  test(
    'ttsSelectorProvider hüllt Systemstimme und Offline-Stimme in den Fokus',
    () {
      fakeAsync((async) {
        final port = _FakeFocus();
        final container = ProviderContainer(
          overrides: [
            audioFocusPortProvider.overrideWithValue(port),
            systemTtsProvider.overrideWithValue(_StubTts()),
            sherpaTtsProvider.overrideWithValue(_StubTts()),
          ],
        );
        addTearDown(container.dispose);
        final selector = container.read(ttsSelectorProvider);
        expect(selector.system, isA<DuckingTextToSpeech>());
        expect(selector.sherpa, isA<DuckingTextToSpeech>());
        unawaited(selector.system.speak('Hallo'));
        async.flushMicrotasks();
        unawaited(selector.sherpa!.speak('Hallo'));
        async.flushMicrotasks();
        expect(port.log.where((e) => e == '+duck'), hasLength(2));
        async.elapse(const Duration(seconds: 10));
      });
    },
  );

  test('Sherpa-Wiedergabe setzt den Audiokontext vor dem Abspielen', () async {
    final player = _FakeAudioPlayer();
    final playback = AudioplayersPlayback(player);
    final done = playback.play(Wav(Int16List(160)));
    await Future<void>.delayed(Duration.zero);
    expect(player.calls, ['context', 'play']);
    expect(player.context, same(AudioplayersPlayback.context));
    player.complete.add(null);
    await done;
  });

  group('ChannelAudioFocusPort', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(audioFocusChannelName);
    final calls = <MethodCall>[];
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
            calls.add(c);
            return c.method == 'acquire' ? true : null;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('Art geht als Name an die Plattform', () async {
      final port = ChannelAudioFocusPort();
      expect(await port.acquire(AudioFocusKind.duck), isTrue);
      await port.release(AudioFocusKind.listen);
      expect(calls.map((c) => '${c.method}:${(c.arguments as Map)['kind']}'), [
        'acquire:duck',
        'release:listen',
      ]);
    });

    test('Fokuswechsel der Plattform kommt als Ereignis', () async {
      final port = ChannelAudioFocusPort();
      final seen = <String>[];
      final sub = port.changes.listen((c) => seen.add('$c'));
      Future<void> send(Object? args) => TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .handlePlatformMessage(
            audioFocusChannelName,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('focusChanged', args),
            ),
            (_) {},
          );
      await send({'kind': 'listen', 'state': 'lost'});
      await send({'kind': 'listen', 'state': 'gained'});
      await send({'kind': 'x', 'state': 'lost'}); // unknown: ignored
      await send('kaputt');
      await sub.cancel();
      expect(seen, [
        'AudioFocusChange(listen, lost: true)',
        'AudioFocusChange(listen, lost: false)',
      ]);
    });

    test('ohne Plattformseite: false, kein Fehler', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      final port = ChannelAudioFocusPort();
      expect(await port.acquire(AudioFocusKind.duck), isFalse);
      await port.release(AudioFocusKind.duck);
    });
  });
}
