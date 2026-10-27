import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/sherpa_speaker.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

class _Session implements SpeakerSession {
  _Session(this.hangs);
  final bool hangs;
  bool disposed = false;

  @override
  Future<Float32List> embed(Int16List pcm) async {
    if (hangs) throw TimeoutException('hang');
    return Float32List(2);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  late Directory dir;
  late SherpaSpeakerEmbedder embedder;
  late List<_Session> started;
  late List<bool> script;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('spk');
    final file = SpeechModelCatalog.speakerCamPlus.files.single;
    File('${dir.path}/${file.name}')
        .writeAsBytesSync(Uint8List(file.sizeBytes));
    started = [];
    script = [];
    embedder = SherpaSpeakerEmbedder(
      model: SpeechModelCatalog.speakerCamPlus,
      directory: dir.path,
      sessionFactory: (_) async {
        final s = _Session(script[started.length]);
        started.add(s);
        return s;
      },
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  final pcm = Int16List(16000);

  test('first hang restarts once, second hang fails until release', () async {
    script = [true, true, false];
    await expectLater(embedder.embed(pcm), throwsA(isA<TimeoutException>()));
    await expectLater(embedder.embed(pcm), throwsA(isA<TimeoutException>()));
    expect(started, hasLength(2));
    // failed: no third isolate, immediate error
    await expectLater(embedder.embed(pcm), throwsA(isA<VoiceException>()));
    expect(started, hasLength(2));
    await embedder.release();
    expect(await embedder.embed(pcm), hasLength(2));
    expect(started, hasLength(3));
  });

  test('a single hang recovers with one new isolate', () async {
    script = [true, false];
    await expectLater(embedder.embed(pcm), throwsA(isA<TimeoutException>()));
    expect(await embedder.embed(pcm), hasLength(2));
    expect(started, hasLength(2));
  });

  test(
    'model-load kind=speaker wird einmal beim Laden geloggt (WP160)',
    () async {
      final lines = <String>[];
      final old = voiceLogSink;
      voiceLogSink = lines.add;
      addTearDown(() => voiceLogSink = old);
      script = [false];
      await embedder.embed(pcm);
      await embedder.embed(pcm);
      final loads = lines.where((l) => l.contains(' model-load ')).toList();
      expect(loads, hasLength(1));
      expect(
        loads.single,
        matches(r'model-load .*model=speaker-campplus kind=speaker ms=\d+$'),
      );
    },
  );
}
