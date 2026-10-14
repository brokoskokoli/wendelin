import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/debug/wake_test_audio.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/wav_audio_input.dart';

void main() {
  late Directory base;

  setUp(() {
    base = Directory.systemTemp.createTempSync('wake_audio');
    Directory('${base.path}/e2e').createSync();
    addTearDown(() => base.deleteSync(recursive: true));
  });

  void write(String name, String content) =>
      File('${base.path}/e2e/$name').writeAsStringSync(content);

  test('ohne wake.json: das Mikrofon des Dienstes', () async {
    expect(await debugWakeAudio(base: base), isNull);
  });

  test('wake.json mit WAV: die Datei statt des Mikrofons', () async {
    File('${base.path}/e2e/x.wav')
        .writeAsBytesSync(Wav(Int16List.fromList([1, 2, 3, 4])).encode());
    write('wake.json', '{"audio": "x.wav", "leadingSilence": 12}');
    final input = await debugWakeAudio(base: base);
    expect(input, isA<WavAudioInput>());
    expect(
      (input! as WavAudioInput).leadingSilence,
      const Duration(seconds: 12),
    );
    expect((input as WavAudioInput).samples, [1, 2, 3, 4]);
  });

  test('ungültig (Pfad, kein JSON): kein Ersatz', () async {
    write('wake.json', '{"audio": "../x.wav"}');
    expect(await debugWakeAudio(base: base), isNull);
    write('wake.json', 'kaputt');
    expect(await debugWakeAudio(base: base), isNull);
  });
}
