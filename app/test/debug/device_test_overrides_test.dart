import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/debug/device_test_overrides.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/wav_audio_input.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('wendelin-e2e'));
  tearDown(() => dir.deleteSync(recursive: true));

  void writeWav(String name, List<int> samples) =>
      File('${dir.path}/$name')
          .writeAsBytesSync(Wav(Int16List.fromList(samples)).encode());

  group('WavAudioInput', () {
    test('Stille, Aufnahme, dann Stille bis stop', () async {
      final input = WavAudioInput(
        Int16List.fromList(List.filled(480, 1000)),
        speed: 20,
        leadingSilence: const Duration(milliseconds: 20),
      );
      final frames = <Int16List>[];
      final sub = input.start().listen(frames.add);
      expect(input.isRunning, isTrue);
      expect(() => input.start(), throwsStateError);
      while (frames.length < 6) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      await input.stop();
      await sub.cancel();
      expect(input.isRunning, isFalse);
      expect(input.starts, 1);
      // 20 ms = 320 Samples je Frame: 1 Frame Stille, 480 Samples Aufnahme
      // (1,5 Frames), danach Stille.
      expect(frames.first.every((s) => s == 0), isTrue);
      expect(frames[1].every((s) => s == 1000), isTrue);
      expect(frames[2].sublist(0, 160).every((s) => s == 1000), isTrue);
      expect(frames[2].sublist(160).every((s) => s == 0), isTrue);
      expect(frames[3].every((s) => s == 0), isTrue);
      expect(input.endOfRecording, isNotNull);
    });

    test(
      'stop ohne Zuhörer hängt nicht; erneuter Start spielt von vorn',
      () async {
        final input = WavAudioInput(Int16List.fromList([5, 5]), speed: 50);
        input.start();
        await input.stop();
        final first = await input.start().first;
        await input.stop();
        expect(input.starts, 2);
        expect(first.every((s) => s == 0), isTrue, reason: 'Vorlauf-Stille');
      },
    );

    test('Datei mit 16 kHz', () {
      writeWav('a.wav', [1, 2, 3]);
      expect(WavAudioInput.file('${dir.path}/a.wav').samples, [1, 2, 3]);
      File('${dir.path}/b.wav')
          .writeAsBytesSync(Wav(Int16List(4), sampleRate: 8000).encode());
      expect(
        () => WavAudioInput.file('${dir.path}/b.wav'),
        throwsFormatException,
      );
    });
  });

  group('deviceTestOverrides', () {
    test('ohne Datei: keine', () async {
      expect(await deviceTestOverrides(base: dir), isEmpty);
    });

    test('ungültige Datei: keine (nur protokolliert)', () async {
      Directory('${dir.path}/$deviceTestFolder').createSync();
      File('${dir.path}/$deviceTestFolder/overlay.json').writeAsStringSync('[');
      expect(await deviceTestOverrides(base: dir), isEmpty);
    });

    test('WAV und Skript-Provider aus overlay.json', () async {
      final e2e = Directory('${dir.path}/$deviceTestFolder')..createSync();
      File('${e2e.path}/x.wav').writeAsBytesSync(Wav(Int16List(8)).encode());
      File('${e2e.path}/overlay.json').writeAsStringSync('''
{"audio": "x.wav",
 "turns": [{"tool": "obsidian__append_daily_note",
            "arguments": {"text": "Zahnarzt angerufen"}},
           {"text": "Erledigt."}]}''');
      final c = ProviderContainer(
        overrides: await deviceTestOverrides(base: dir),
      );
      addTearDown(c.dispose);
      expect(c.read(audioInputProvider), isA<WavAudioInput>());
      final config = (await c.read(storedProviderConfigProvider.future))!;
      expect(config.primary.privacy, PrivacyLevel.local);
      expect(config.nameOf(config.primary.profileId), 'Skript (Gerätetest)');
      final events = await config.primary.provider
          .chat(
            ChatRequest(
              model: 'skript',
              messages: [Message.user('Ergänze meine Tagesnotiz')],
              maxTokens: 100,
            ),
          )
          .toList();
      final call = events.whereType<ToolCallComplete>().single.call;
      expect(call.name, 'obsidian__append_daily_note');
      expect(call.argumentsJson, '{"text":"Zahnarzt angerufen"}');
    });

    test('nur Dateinamen, bekannte Züge', () {
      for (final json in [
        '{"audio": "../x.wav"}',
        '{"audio": ""}',
        '{"turns": [{"nix": 1}]}',
        '"text"',
      ]) {
        expect(
          () => parseDeviceTestOverrides(json, dir.path),
          throwsFormatException,
          reason: json,
        );
      }
      expect(parseDeviceTestOverrides('{}', dir.path), isEmpty);
    });
  });
}
