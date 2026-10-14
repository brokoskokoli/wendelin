import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/sherpa_tts.dart';
import 'package:wendelin/platform/voice/system_tts.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Emulates the Android side of `flutter_tts` (channel `flutter_tts`) with
/// `awaitSpeakCompletion(true)`: `speak` answers when the utterance is over
/// (after [speakTime]) or with 0 when `stop` comes first.
final class FakeTtsChannel {
  FakeTtsChannel({
    this.engines = const ['org.example.tts'],
    this.speakTime = const Duration(milliseconds: 30),
  });

  List<String> engines;
  Duration speakTime;
  List<Object> voices = [
    {'name': 'de-de-x-net', 'locale': 'de-DE', 'network_required': '1'},
    {'name': 'de-de-x-local', 'locale': 'de-DE', 'network_required': '0'},
    {'name': 'fr-fr-x-local', 'locale': 'fr-FR'},
    {'name': '', 'locale': 'en-US'},
    'kaputt',
  ];
  bool missing = false;
  final calls = <MethodCall>[];
  Completer<int>? _speaking;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), _handle);
  }

  Future<Object?> _handle(MethodCall call) async {
    if (missing) throw MissingPluginException();
    calls.add(call);
    switch (call.method) {
      case 'getEngines':
        return engines;
      case 'getVoices':
        return voices;
      case 'speak':
        final c = _speaking = Completer<int>();
        Timer(speakTime, () {
          if (!c.isCompleted) c.complete(1);
        });
        return c.future;
      case 'stop':
        final c = _speaking;
        if (c != null && !c.isCompleted) c.complete(0);
        return 1;
      default:
        return 1;
    }
  }

  List<String> get methods => [for (final c in calls) c.method];
}

final class FakeSynthesizer implements SpeechSynthesizer {
  FakeSynthesizer({this.delay = Duration.zero});

  final Duration delay;
  final calls = <(String, String, double)>[];

  @override
  Future<Wav> synthesize(
    String text, {
    required String voiceId,
    double speed = 1.0,
  }) async {
    calls.add((text, voiceId, speed));
    await Future<void>.delayed(delay);
    return Wav(floatToPcm(Float32List(1600)));
  }

  @override
  Future<void> dispose() async {}
}

final class FakePlayback implements AudioPlayback {
  FakePlayback({this.time = const Duration(milliseconds: 30)});

  final Duration time;
  Completer<void>? _done;
  int played = 0;

  @override
  Future<void> play(Wav wav) {
    played++;
    final c = _done = Completer<void>();
    Timer(time, () {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  @override
  Future<void> stop() async {
    final c = _done;
    if (c != null && !c.isCompleted) c.complete();
  }
}

const _voice = SherpaVoice(
  id: 'tts-de-thorsten',
  language: 'de',
  name: 'Deutsch – Thorsten',
  files: PiperVoiceFiles(model: 'm', tokens: 't', dataDir: 'd'),
);
const _voiceFr = SherpaVoice(
  id: 'tts-fr-siwis',
  language: 'fr',
  name: 'Français – Siwis',
  files: PiperVoiceFiles(model: 'm', tokens: 't', dataDir: 'd'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SystemTextToSpeech', () {
    late FakeTtsChannel channel;
    setUp(() => (channel = FakeTtsChannel()).install());

    textToSpeechContract(
      () => SystemTextToSpeech(tts: FlutterTts()),
      name: 'SystemTextToSpeech (Mock-Kanal)',
    );

    test('ohne Engine nicht verfügbar, ohne Plugin auch nicht', () async {
      channel.engines = [];
      final tts = SystemTextToSpeech(tts: FlutterTts());
      expect(await tts.isAvailable, isFalse);
      channel.missing = true;
      expect(await tts.isAvailable, isFalse);
    });

    test('Stimmen ohne Netz, ohne kaputte Einträge', () async {
      final tts = SystemTextToSpeech(tts: FlutterTts());
      final voices = await tts.voices();
      expect(voices.map((v) => v.id), ['de-de-x-local', 'fr-fr-x-local']);
      expect(voices.first.language, 'de-DE');
      expect(offlineVoiceFor(voices, null, 'es'), isNull);
      expect(offlineVoiceFor(voices, null, null)!.id, 'de-de-x-local');
      expect(await tts.voices(), same(voices)); // cached
    });

    List<Object?> setVoices() => [
      for (final c in channel.calls)
        if (c.method == 'setVoice') c.arguments,
    ];

    test('Stimme, Sprache und Tempo gehen an die Engine', () async {
      final tts = SystemTextToSpeech(tts: FlutterTts());
      await tts.speak('Hallo', voice: 'fr-fr-x-local', rate: 1.5);
      await tts.speak('Hallo', language: 'de-AT');
      expect(setVoices(), [
        {'name': 'fr-fr-x-local', 'locale': 'fr-FR'},
        {'name': 'de-de-x-local', 'locale': 'de-DE'},
      ]);
      final rates = [
        for (final c in channel.calls)
          if (c.method == 'setSpeechRate') c.arguments,
      ];
      expect(rates, [0.75, 0.5]);
      expect(channel.methods, isNot(contains('setLanguage')));
      expect(
        channel.methods.where((m) => m == 'awaitSpeakCompletion'),
        hasLength(1),
      );
    });

    test(
      'ohne gewählte Stimme nie die Netzstimme oder der Engine-Standard',
      () async {
        final tts = SystemTextToSpeech(tts: FlutterTts());
        await tts.speak('Hallo');
        await tts.speak('Hallo', voice: 'de-de-x-net', language: 'de');
        await tts.speak('Hallo', voice: 'tts-de-thorsten', language: 'de');
        expect(
          setVoices(),
          everyElement({'name': 'de-de-x-local', 'locale': 'de-DE'}),
        );
        expect(setVoices(), hasLength(3));
      },
    );

    test('keine Offline-Stimme der Sprache: Fehler statt Netzstimme', () async {
      final tts = SystemTextToSpeech(tts: FlutterTts());
      await expectLater(
        tts.speak('Hello', language: 'en'),
        throwsA(
          isA<VoiceException>().having(
            (e) => e.kind,
            'kind',
            VoiceErrorKind.unavailable,
          ),
        ),
      );
      expect(channel.methods, isNot(contains('speak')));
      expect(tts.state, TtsState.idle);
    });

    test(
      'nur Netzstimmen: nicht verfügbar, TtsSelector nimmt sherpa',
      () async {
        channel.voices = [
          {'name': 'de-net', 'locale': 'de-DE', 'network_required': '1'},
        ];
        final system = SystemTextToSpeech(tts: FlutterTts());
        expect(await system.isAvailable, isFalse);
        final sherpa = FakeTextToSpeech();
        final selection = await TtsSelector(
          system: system,
          sherpa: sherpa,
        ).select(language: 'de');
        expect(selection.engine, TtsEngine.sherpa);
      },
    );

    test(
      'System ohne Offline-Stimme für Französisch: sherpa spricht',
      () async {
        channel.voices = [
          {'name': 'de-de-x-local', 'locale': 'de-DE'},
        ];
        final selection = await TtsSelector(
          system: SystemTextToSpeech(tts: FlutterTts()),
          sherpa: FakeTextToSpeech(),
        ).select(language: 'fr');
        expect(selection.engine, TtsEngine.sherpa);
      },
    );

    test('Äußerungen nacheinander; stop verwirft wartende', () async {
      final tts = SystemTextToSpeech(tts: FlutterTts());
      final a = tts.speak('eins');
      final b = tts.speak('zwei');
      await tts.states.firstWhere((s) => s == TtsState.speaking);
      await tts.stop();
      await Future.wait([a, b]);
      expect(channel.methods.where((m) => m == 'speak'), hasLength(1));
      expect(tts.state, TtsState.idle);
    });

    test('Zeitlimit: hängende Engine wird gestoppt', () async {
      channel.speakTime = const Duration(seconds: 5);
      final tts = SystemTextToSpeech(
        tts: FlutterTts(),
        timeout: const Duration(milliseconds: 20),
      );
      await tts.speak('hängt');
      expect(channel.methods, contains('stop'));
      expect(tts.state, TtsState.idle);
    });
  });

  group('SherpaTextToSpeech', () {
    textToSpeechContract(
      () => SherpaTextToSpeech(
        installed: () async => const [_voice],
        synthesizer: FakeSynthesizer(),
        playback: FakePlayback(),
      ),
      name: 'SherpaTextToSpeech (Attrappen)',
    );

    test('ohne Stimme nicht verfügbar; speak meldet modelMissing', () async {
      final tts = SherpaTextToSpeech(
        installed: () async => const [],
        synthesizer: FakeSynthesizer(),
        playback: FakePlayback(),
      );
      expect(await tts.isAvailable, isFalse);
      expect(await tts.voices(), isEmpty);
      await expectLater(
        tts.speak('Hallo'),
        throwsA(
          isA<VoiceException>().having(
            (e) => e.kind,
            'kind',
            VoiceErrorKind.modelMissing,
          ),
        ),
      );
      expect(tts.state, TtsState.idle);
    });

    test('Stimmenwahl: Id, sonst Sprache, sonst erste', () async {
      final synth = FakeSynthesizer();
      final tts = SherpaTextToSpeech(
        installed: () async => const [_voice, _voiceFr],
        synthesizer: synth,
        playback: FakePlayback(time: Duration.zero),
      );
      expect((await tts.voices()).map((v) => v.language), ['de', 'fr']);
      await tts.speak('a', voice: 'tts-fr-siwis');
      await tts.speak('b', language: 'fr-CA', rate: 1.2);
      await tts.speak('c', language: 'en');
      await tts.speak('d', voice: 'unbekannt');
      expect(synth.calls, [
        ('a', 'tts-fr-siwis', 1.0),
        ('b', 'tts-fr-siwis', 1.2),
        ('c', 'tts-de-thorsten', 1.0),
        ('d', 'tts-de-thorsten', 1.0),
      ]);
    });

    test(
      'Stimmenwahl je Sprache (WP66): bevorzugte Stimme, sonst Standard',
      () async {
        const kerstin = SherpaVoice(
          id: 'tts-de-kerstin',
          language: 'de',
          name: 'Kerstin',
          files: PiperVoiceFiles(model: 'm', tokens: 't', dataDir: 'd'),
        );
        final synth = FakeSynthesizer();
        var chosen = <String, String>{'de': 'tts-de-kerstin'};
        final tts = SherpaTextToSpeech(
          installed: () async => const [_voice, kerstin, _voiceFr],
          synthesizer: synth,
          playback: FakePlayback(time: Duration.zero),
          preferred: () => chosen,
        );
        await tts.speak('a', language: 'de');
        await tts.speak('b', voice: 'tts-de-thorsten', language: 'de');
        chosen = {'de': 'tts-de-fehlt', 'fr': 'tts-de-kerstin'};
        await tts.speak('c', language: 'de');
        await tts.speak('d', language: 'fr');
        expect(synth.calls.map((c) => c.$2), [
          'tts-de-kerstin',
          'tts-de-thorsten',
          'tts-de-thorsten',
          'tts-fr-siwis',
        ]);
      },
    );

    test('stop verwirft wartende Äußerungen', () async {
      final playback = FakePlayback(time: const Duration(seconds: 5));
      final tts = SherpaTextToSpeech(
        installed: () async => const [_voice],
        synthesizer: FakeSynthesizer(),
        playback: playback,
      );
      final a = tts.speak('eins');
      final b = tts.speak('zwei');
      await tts.states.firstWhere((s) => s == TtsState.speaking);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tts.stop();
      await Future.wait([a, b]);
      expect(playback.played, 1);
    });
  });

  test('stop während der Synthese: nichts wird abgespielt', () async {
    final playback = FakePlayback();
    final tts = SherpaTextToSpeech(
      installed: () async => const [_voice],
      synthesizer: FakeSynthesizer(delay: const Duration(milliseconds: 30)),
      playback: playback,
    );
    final a = tts.speak('eins');
    await tts.states.firstWhere((s) => s == TtsState.speaking);
    await tts.stop();
    await a;
    expect(playback.played, 0);
    expect(tts.state, TtsState.idle);
  });

  test('PiperVoiceFiles.find: Ordner mit onnx, tokens, espeak-ng-data', () {
    final tmp = Directory.systemTemp.createTempSync('piper');
    addTearDown(() => tmp.deleteSync(recursive: true));
    expect(PiperVoiceFiles.find(Directory('${tmp.path}/fehlt')), isNull);
    expect(PiperVoiceFiles.find(tmp), isNull);
    final v = Directory('${tmp.path}/vits-x')..createSync();
    File('${v.path}/de.onnx').writeAsStringSync('x');
    File('${v.path}/tokens.txt').writeAsStringSync('x');
    Directory('${v.path}/espeak-ng-data').createSync();
    final files = PiperVoiceFiles.find(tmp)!;
    expect(files.model, '${v.path}/de.onnx');
    expect(files.dataDir, '${v.path}/espeak-ng-data');
  });
}
