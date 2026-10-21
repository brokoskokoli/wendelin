// WP118 (K88): Antwort als Gesprächston - Schalter, Wiederherstellung nach
// Stopp/Fehler, Audiokontext und Kanal.
import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/channel_audio_focus_port.dart';
import 'package:wendelin/platform/voice/audio_playback.dart';
import 'package:wendelin/platform/voice/ducking_tts.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

final class _Focus implements AudioFocusPort {
  final log = <String>[];

  @override
  Stream<AudioFocusChange> get changes => const Stream.empty();

  @override
  Future<bool> acquire(AudioFocusKind kind) async {
    log.add('+${kind.name}');
    return true;
  }

  @override
  Future<void> release(AudioFocusKind kind) async => log.add('-${kind.name}');
}

final class _Route implements SpeechRoutePort {
  _Route(this.log, {this.device = 'speaker'});
  final List<String> log;
  final String? device;

  @override
  Future<String?> enter() async {
    log.add('enter');
    return device;
  }

  @override
  Future<void> leave() async => log.add('leave');
}

final class _SlowRoute implements SpeechRoutePort {
  _SlowRoute(this.log, this.result);
  final List<String> log;
  final Future<String?> result;

  @override
  Future<String?> enter() {
    log.add('enter');
    return result;
  }

  @override
  Future<void> leave() async => log.add('leave');
}

final class _Tts implements TextToSpeech {
  _Tts({this.fail = false});
  final bool fail;

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
  }) async {
    if (fail) throw StateError('engine');
  }

  @override
  Future<void> stop() async {}
}

final class _Player implements AudioPlayer {
  final contexts = <AudioContext>[];
  final complete = StreamController<void>.broadcast();

  /// Holds `setAudioContext` (the context is recorded when it is released).
  Completer<void>? contextGate;
  var plays = 0;
  var stops = 0;

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
  Future<void> stop() async => stops++;

  Future<void> close() => complete.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late List<String> events;
  late _Focus focus;
  late List<String> logLines;

  setUp(() {
    events = [];
    focus = _Focus();
    logLines = [];
    voiceLogSink = logLines.add;
  });

  SpeechFocus build({
    Future<bool> Function()? communication,
    String? device = 'speaker',
  }) => SpeechFocus(
    focus,
    route: _Route(events, device: device),
    communication: communication ?? () async => true,
  );

  group('SpeechFocus mit Gesprächston', () {
    test('Schalter aus: kein Wechsel, nur der Fokus', () {
      fakeAsync((async) {
        final f = build(communication: () async => false);
        f.begin();
        async.flushMicrotasks();
        expect(f.routed, isFalse);
        f.end(f.generation);
        async.elapse(const Duration(seconds: 5));
        expect(events, isEmpty);
        expect(focus.log, ['+duck', '-duck']);
        expect(logLines.where((l) => l.contains('speech-route')), isEmpty);
      });
    });

    test('ohne Schalter-Quelle bleibt alles beim Alten', () {
      fakeAsync((async) {
        final f = SpeechFocus(focus, route: _Route(events));
        f.begin();
        async.flushMicrotasks();
        expect(f.routed, isFalse);
        expect(events, isEmpty);
      });
    });

    test('an: ein Wechsel je Antwort, Rückgabe nach der Haltezeit', () {
      fakeAsync((async) {
        final f = build();
        f.begin();
        async.flushMicrotasks();
        expect(f.routed, isTrue);
        f.end(f.generation);
        f.begin(); // next sentence
        async.flushMicrotasks();
        f.end(f.generation);
        expect(events, ['enter']);
        async.elapse(const Duration(seconds: 5));
        expect(events, ['enter', 'leave']);
        expect(f.routed, isFalse);
      });
    });

    test('Logzeile speech-route ohne Inhalt', () {
      fakeAsync((async) {
        final f = build(device: 'external');
        f.begin();
        async.flushMicrotasks();
        f.end(f.generation);
        async.elapse(const Duration(seconds: 5));
        final lines = logLines.where((l) => l.contains('speech-route'));
        expect(lines, hasLength(2));
        expect(
          lines.first,
          allOf(contains('mode=communication'), contains('device=external')),
        );
        expect(lines.last, contains('mode=normal'));
      });
    });

    test('Stopp gibt den Zustand sofort zurück, doppelt nur einmal', () {
      fakeAsync((async) {
        final f = build();
        f.begin();
        async.flushMicrotasks();
        f.drop();
        f.drop();
        async.flushMicrotasks();
        expect(events, ['enter', 'leave']);
        expect(focus.log, ['+duck', '-duck']);
        async.elapse(const Duration(seconds: 5));
        expect(events, ['enter', 'leave']);
      });
    });

    test('Fehler der Stimme: Zustand kommt nach der Haltezeit zurück', () {
      fakeAsync((async) {
        final f = build();
        final tts = DuckingTextToSpeech(_Tts(fail: true), f);
        Object? error;
        tts.speak('Hallo').catchError((Object e) => error = e);
        async.flushMicrotasks();
        expect(error, isA<StateError>());
        async.elapse(const Duration(seconds: 5));
        expect(events, ['enter', 'leave']);
        expect(f.routed, isFalse);
      });
    });

    test('Stopp über die Stimme räumt auf', () {
      fakeAsync((async) {
        final f = build();
        final tts = DuckingTextToSpeech(_Tts(), f);
        unawaited(tts.speak('Hallo'));
        async.flushMicrotasks();
        unawaited(tts.stop());
        async.flushMicrotasks();
        expect(events, ['enter', 'leave']);
      });
    });

    test('Wechsel schlägt fehl: trotzdem Rückgabe, Fokus wird geholt', () {
      fakeAsync((async) {
        final f = build(device: null);
        f.begin();
        async.flushMicrotasks();
        expect(focus.log, ['+duck']);
        expect(logLines.single, contains('device=failed'));
        // Not switched: the player must not use the call usage (K88).
        expect(f.routed, isFalse);
        f.drop();
        async.flushMicrotasks();
        expect(events, ['enter', 'leave']);
      });
    });

    test('Stopp während die Einstellung gelesen wird: kein Wechsel', () {
      fakeAsync((async) {
        final setting = Completer<bool>();
        final f = build(communication: () => setting.future);
        f.begin();
        async.flushMicrotasks();
        f.drop();
        setting.complete(true);
        async.elapse(const Duration(seconds: 10));
        expect(f.routed, isFalse);
        expect(events, isEmpty);
      });
    });

    test('Stopp während der Wechsel läuft: Rückgabe, nicht gerouted', () {
      fakeAsync((async) {
        final enter = Completer<String?>();
        final route = _SlowRoute(events, enter.future);
        final f = SpeechFocus(
          focus,
          route: route,
          communication: () async => true,
        );
        f.begin();
        async.flushMicrotasks();
        f.drop();
        enter.complete('speaker');
        async.elapse(const Duration(seconds: 10));
        expect(f.routed, isFalse);
        expect(events, ['enter', 'leave']);
      });
    });

    test('Einstellung unlesbar: normaler Pfad statt Fehler', () {
      fakeAsync((async) {
        final f = build(communication: () async => throw StateError('db'));
        f.begin();
        async.flushMicrotasks();
        expect(f.routed, isFalse);
        expect(events, isEmpty);
        expect(focus.log, ['+duck']);
      });
    });
  });

  group('AudioplayersPlayback', () {
    Future<void> playOnce(AudioplayersPlayback p, _Player player) async {
      final done = p.play(Wav(Int16List(160)));
      await Future<void>.delayed(Duration.zero);
      player.complete.add(null);
      await done;
    }

    test(
      'Gesprächston: Usage voiceCommunication, danach wieder normal',
      () async {
        final player = _Player();
        addTearDown(player.close);
        var comm = true;
        final p = AudioplayersPlayback(player, () => comm);
        await playOnce(p, player);
        comm = false;
        await playOnce(p, player);
        await playOnce(p, player); // unchanged: no new context
        expect(player.contexts, [
          AudioplayersPlayback.communicationContext,
          AudioplayersPlayback.context,
        ]);
        // The log tells the usage really used (not a guess of the focus).
        expect(logLines.where((l) => l.contains('usage=')).toList(), [
          contains('usage=voice_communication'),
          contains('usage=assistant'),
        ]);
        final a = AudioplayersPlayback.communicationContext.android;
        expect(a.usageType, AndroidUsageType.voiceCommunication);
        expect(a.contentType, AndroidContentType.speech);
        expect(a.audioFocus, AndroidAudioFocus.gainTransientMayDuck);
        // audioplayers sets audioManager.mode = audioMode on a context change
        // (WrappedPlayer.kt:171); normal would undo the call mode.
        expect(a.audioMode, AndroidAudioMode.inCommunication);
      },
    );

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

    test(
      'Schalter kippt während des Kontextwechsels: letzter Kontext passt',
      () async {
        final player = _Player()..contextGate = Completer<void>();
        addTearDown(player.close);
        var comm = true;
        final p = AudioplayersPlayback(player, () => comm);
        final done = p.play(Wav(Int16List(160)));
        await Future<void>.delayed(Duration.zero);
        comm = false;
        player.contextGate!.complete();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        player.complete.add(null);
        await done;
        expect(player.contexts.last, AudioplayersPlayback.context);
        // The next play with the same switch needs no further change.
        final n = player.contexts.length;
        await playOnce(p, player);
        expect(player.contexts, hasLength(n));
      },
    );

    test('Schalter aus: Kontext wie bisher (Assistent)', () async {
      final player = _Player();
      addTearDown(player.close);
      final p = AudioplayersPlayback(player);
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

  group('ChannelSpeechRoutePort', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(audioFocusChannelName);
    final calls = <String>[];
    Future<Object?> Function(MethodCall)? handler;
    setUp(() {
      calls.clear();
      handler = (c) async {
        calls.add(c.method);
        if (c.method == 'audioMode') return 3;
        return c.method == 'enterCommunication' ? 'speaker' : null;
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) => handler!(c));
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('enter und leave gehen an die Plattform', () async {
      final port = ChannelSpeechRoutePort();
      expect(await port.enter(), 'speaker');
      expect(await port.audioMode(), 3);
      await port.leave();
      expect(calls, ['enterCommunication', 'audioMode', 'leaveCommunication']);
    });

    test('Plattformfehler werden verschluckt', () async {
      handler = (c) async => throw PlatformException(code: 'failed');
      final port = ChannelSpeechRoutePort();
      expect(await port.enter(), isNull);
      expect(await port.audioMode(), isNull);
      await port.leave();
    });

    test('ohne Plattformseite kein Fehler', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      final port = ChannelSpeechRoutePort();
      expect(await port.enter(), isNull);
      expect(await port.audioMode(), isNull);
      await port.leave();
    });
  });
}
