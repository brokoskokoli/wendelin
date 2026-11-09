// Systemstimme auf gewähltem Ausgang (WP188 Teil C2): Datei-Synthese, Weiche,
// Rückfall, Stopp, Löschen der Datei, WAV-Formate der Engine.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/sherpa_tts.dart';
import 'package:wendelin/platform/voice/system_tts.dart';
import 'package:wendelin/platform/voice/system_tts_render.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

enum _Synth { complete, error, hang, empty }

/// `flutter_tts` channel with `synthesizeToFile` as the Android plugin does it
/// without `awaitSynthCompletion`: answers at once, the end comes as event.
final class _Channel {
  _Channel(this.dir);

  final Directory dir;
  var mode = _Synth.complete;
  var cancelEvent = true; // the plugin reports a stop as speak.onCancel
  Uint8List? wav;
  final calls = <MethodCall>[];
  final files = <String>[];
  Completer<void>? speaking;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), _handle);
  }

  void _emit(String method, Object? args) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'flutter_tts',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          null,
        );
  }

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'getEngines':
        return ['e'];
      case 'getVoices':
        return [
          {'name': 'de-local', 'locale': 'de-DE', 'network_required': '0'},
        ];
      case 'synthesizeToFile':
        final path = (call.arguments as Map)['fileName'] as String;
        files.add(path);
        if (mode != _Synth.hang) {
          File(path).writeAsBytesSync(
            mode == _Synth.empty ? _wav(1, 16, const []) : wav ?? _mono(),
          );
        }
        if (mode == _Synth.error) {
          Timer.run(() => _emit('synth.onError', 'x'));
        } else if (mode != _Synth.hang) {
          Timer.run(() => _emit('synth.onComplete', true));
        }
        return 1;
      case 'speak':
        final c = speaking = Completer<void>();
        Timer(const Duration(milliseconds: 10), () {
          if (!c.isCompleted) c.complete();
        });
        await c.future;
        return 1;
      case 'stop':
        if (mode == _Synth.hang && cancelEvent) _emit('speak.onCancel', true);
        final c = speaking;
        if (c != null && !c.isCompleted) c.complete();
        return 1;
      default:
        return 1;
    }
  }

  List<String> get methods => [for (final c in calls) c.method];
}

Uint8List _wav(
  int channels,
  int bits,
  List<num> samples, {
  int rate = 22050,
  int format = 1,
}) {
  final width = bits ~/ 8;
  final dataLen = samples.length * width;
  final d = ByteData(44 + dataLen);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      d.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  d.setUint32(4, 36 + dataLen, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  d
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, format, Endian.little)
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * channels * width, Endian.little)
    ..setUint16(32, channels * width, Endian.little)
    ..setUint16(34, bits, Endian.little);
  tag(36, 'data');
  d.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final at = 44 + i * width;
    final v = samples[i];
    if (format == 3) {
      d.setFloat32(at, v.toDouble(), Endian.little);
    } else if (bits == 8) {
      d.setUint8(at, v.toInt());
    } else if (bits == 16) {
      d.setInt16(at, v.toInt(), Endian.little);
    } else {
      d.setInt32(at, v.toInt(), Endian.little);
    }
  }
  return d.buffer.asUint8List();
}

Uint8List _mono() => _wav(1, 16, List.filled(2205, 1000), rate: 22050);

final class _Playback implements AudioPlayback {
  final played = <Wav>[];
  var stops = 0;
  Completer<void>? hold;
  var filesWhilePlaying = -1;
  late Directory dir;

  @override
  Future<void> play(Wav wav) async {
    played.add(wav);
    filesWhilePlaying = _left(dir).length;
    await hold?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    final h = hold;
    if (h != null && !h.isCompleted) h.complete();
  }
}

List<FileSystemEntity> _left(Directory dir) => [
  for (final e in dir.listSync())
    if (e.uri.pathSegments.last.startsWith(SystemSpeechRenderer.prefix)) e,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('wavFromEngineFile', () {
    test('Stereo wird zu Mono gemittelt, Abtastrate bleibt', () {
      final wav = wavFromEngineFile(
        _wav(2, 16, [1000, 3000, -2000, 2000], rate: 24000),
      );
      expect(wav.sampleRate, 24000);
      expect(wav.samples, [2000, 0]);
    });

    test('8 bit, 32 bit und Float werden nach 16 bit gewandelt', () {
      expect(wavFromEngineFile(_wav(1, 8, [128, 255])).samples, [0, 32511]);
      expect(
        wavFromEngineFile(_wav(1, 32, [1073741824])).samples.single,
        16384,
      );
      final f = wavFromEngineFile(
        _wav(1, 32, [0.5, -2.0, double.nan], format: 3),
      );
      expect(f.samples, [16384, -32768, 0]);
    });

    test('Fremdes Format, leer, kein WAV: FormatException', () {
      expect(
        () => wavFromEngineFile(_wav(1, 16, [1], format: 2)),
        throwsFormatException,
      );
      expect(() => wavFromEngineFile(_wav(1, 16, [])), throwsFormatException);
      expect(
        () => wavFromEngineFile(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });

  group('SystemTextToSpeech auf gewähltem Ausgang', () {
    late Directory dir;
    late _Channel channel;
    late _Playback out;
    var chosen = true;

    SystemTextToSpeech make({
      Duration synthTimeout = const Duration(seconds: 5),
    }) {
      final tts = FlutterTts();
      return SystemTextToSpeech(
        tts: tts,
        renderer: SystemSpeechRenderer(
          tts,
          directory: () async => dir,
          timeout: synthTimeout,
        ),
        playback: out,
        hasChoice: () => chosen,
      );
    }

    setUp(() {
      dir = Directory.systemTemp.createTempSync('tts_render_');
      addTearDown(() => dir.deleteSync(recursive: true));
      channel = _Channel(dir)..install();
      out = _Playback()..dir = dir;
      chosen = true;
    });

    test('Wahl gesetzt: Datei, Wiedergabe über den Pfad, Datei weg', () async {
      channel.wav = _wav(1, 16, List.filled(4410, 500), rate: 44100);
      final tts = make();
      final states = <TtsState>[];
      tts.states.listen(states.add);
      await tts.speak('Hallo', voice: 'de-local', rate: 1.5);
      expect(out.played.single.sampleRate, 44100);
      expect(out.played.single.samples, hasLength(4410));
      expect(channel.methods, isNot(contains('speak')));
      final m = channel.methods;
      expect(m.indexOf('setVoice'), lessThan(m.indexOf('synthesizeToFile')));
      expect(
        m.indexOf('setSpeechRate'),
        lessThan(m.indexOf('synthesizeToFile')),
      );
      final args = channel.calls.firstWhere(
        (c) => c.method == 'synthesizeToFile',
      );
      expect((args.arguments as Map)['isFullPath'], isTrue);
      expect((args.arguments as Map)['fileName'], startsWith(dir.path));
      expect(
        out.filesWhilePlaying,
        0,
      ); // gelesen und gelöscht vor dem Abspielen
      expect(_left(dir), isEmpty);
      expect(states, [TtsState.speaking, TtsState.idle]);
    });

    test('keine Wahl: direkter Weg, kein Verzeichnis, keine Datei', () async {
      chosen = false;
      final tts = make();
      await tts.speak('Hallo');
      expect(channel.methods, contains('speak'));
      expect(channel.methods, isNot(contains('synthesizeToFile')));
      expect(out.played, isEmpty);
    });

    test('unlesbare Wahl: direkter Weg', () async {
      final tts = SystemTextToSpeech(
        tts: FlutterTts(),
        renderer: SystemSpeechRenderer(
          FlutterTts(),
          directory: () async => dir,
        ),
        playback: out,
        hasChoice: () => throw StateError('x'),
      );
      await tts.speak('Hallo');
      expect(channel.methods, contains('speak'));
      expect(out.played, isEmpty);
    });

    test('Engine-Fehler: direkter Weg, Datei weg, nichts abgespielt', () async {
      channel.mode = _Synth.error;
      await make().speak('Hallo');
      expect(channel.methods, contains('speak'));
      expect(out.played, isEmpty);
      expect(_left(dir), isEmpty);
    });

    test('Zeitgrenze: Engine gestoppt, direkter Weg, Datei weg', () async {
      channel.mode = _Synth.hang;
      // The hung engine wrote nothing; a half written file must go as well.
      await make(synthTimeout: const Duration(milliseconds: 30)).speak('Hallo');
      expect(channel.methods, containsAllInOrder(['synthesizeToFile', 'stop']));
      expect(channel.methods, contains('speak'));
      expect(out.played, isEmpty);
      expect(_left(dir), isEmpty);
    });

    test('Datei ohne Samples: direkter Weg', () async {
      channel.mode = _Synth.empty;
      await make().speak('Hallo');
      expect(channel.methods, contains('speak'));
      expect(out.played, isEmpty);
      expect(_left(dir), isEmpty);
    });

    for (final event in [true, false]) {
      test(
        'Stopp während der Synthese (Cancel-Ereignis $event): kein Nachlauf, Datei weg',
        () async {
          channel.cancelEvent = event;
          channel.mode = _Synth.hang;
          final tts = make();
          final done = tts.speak('Hallo');
          await tts.states.firstWhere((s) => s == TtsState.speaking);
          await pumpEventQueue();
          File(channel.files.single)
              .writeAsBytesSync(_mono()); // halb geschrieben
          await tts.stop();
          await done.timeout(const Duration(seconds: 2));
          expect(channel.methods, isNot(contains('speak')));
          expect(out.played, isEmpty);
          expect(_left(dir), isEmpty);
          expect(tts.state, TtsState.idle);
          // Next utterance works (no stuck state).
          channel.mode = _Synth.complete;
          await tts.speak('Wieder');
          expect(out.played, hasLength(1));
        },
      );
    }

    test(
      'Stopp während der Wiedergabe: Pfad gestoppt, Ende gemeldet',
      () async {
        out.hold = Completer<void>();
        final tts = make();
        final done = tts.speak('Hallo');
        await tts.states.firstWhere((s) => s == TtsState.speaking);
        while (out.played.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        await tts.stop();
        await done.timeout(const Duration(seconds: 2));
        expect(out.stops, 1);
        expect(_left(dir), isEmpty);
        expect(tts.state, TtsState.idle);
      },
    );

    test('Reste eines Absturzes werden vor der Synthese gelöscht', () async {
      final stale = File('${dir.path}/${SystemSpeechRenderer.prefix}alt.wav')
        ..writeAsBytesSync([1]);
      final other = File('${dir.path}/anderes.wav')..writeAsBytesSync([1]);
      await make().speak('Hallo');
      expect(stale.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
    });
  });
}
