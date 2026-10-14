// WP51: Audioquelle der Aufnahme folgt der Sprachausgabe; die Echo-
// Unterdrückung gehört zur Quelle „Sprachausgabe“ und wird mit der Aufnahme
// angelegt und freigegeben.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:wendelin/platform/voice/capture_profile_follower.dart';
import 'package:wendelin/platform/voice/record_audio_input.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../support/fake_microphone.dart';

/// Records the `RecordConfig` of every started stream.
final class _ConfigRecorder implements AudioRecorder {
  final configs = <RecordConfig>[];
  int stops = 0;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    configs.add(config);
    return const Stream<Uint8List>.empty();
  }

  @override
  Future<String?> stop() async {
    stops++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('Quelle der Aufnahme (RecordPcmRecorder)', () {
    test(
      'Erkennung: VOICE_RECOGNITION ohne Echo-Unterdrückung (Standard)',
      () async {
        final rec = _ConfigRecorder();
        await RecordPcmRecorder(rec).startStream();
        final c = rec.configs.single;
        expect(
          c.androidConfig.audioSource,
          AndroidAudioSource.voiceRecognition,
        );
        expect(c.echoCancel, isFalse);
        expect(c.sampleRate, 16000);
      },
    );

    test('Sprachausgabe: VOICE_COMMUNICATION mit Echo-Unterdrückung', () async {
      final rec = _ConfigRecorder();
      await RecordPcmRecorder(rec).startStream(CaptureProfile.speechOutput);
      final c = rec.configs.single;
      expect(
        c.androidConfig.audioSource,
        AndroidAudioSource.voiceCommunication,
      );
      expect(c.echoCancel, isTrue);
    });

    test(
      'stop gibt die Aufnahme (und mit ihr den Echo-Unterdrücker) frei',
      () async {
        final rec = _ConfigRecorder();
        final recorder = RecordPcmRecorder(rec);
        await recorder.startStream(CaptureProfile.speechOutput);
        await recorder.stop();
        expect(rec.stops, 1);
      },
    );
  });

  group('RecordAudioInput.useProfile', () {
    test(
      'wirkt auf den nächsten Start, nicht auf eine laufende Aufnahme',
      () async {
        final rec = FakePcmRecorder();
        final input = RecordAudioInput(rec);
        expect(input.profile, CaptureProfile.recognition);
        final sub = input.start().listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(input.useProfile(CaptureProfile.speechOutput), isFalse);
        expect(input.profile, CaptureProfile.recognition);
        await input.stop();
        await sub.cancel();

        expect(input.useProfile(CaptureProfile.speechOutput), isTrue);
        final sub2 = input.start().listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await input.stop();
        await sub2.cancel();
        expect(rec.profiles, [
          CaptureProfile.recognition,
          CaptureProfile.speechOutput,
        ]);
      },
    );
  });

  group('Quelle bei laufender Aufnahme (WP64)', () {
    // The barge-in listener records with speechOutput; when the answer ends
    // the pipeline asks for `recognition` while it still runs. The next
    // recording (follow-up window) must get recognition.
    test('Wunsch während der Aufnahme gilt beim nächsten Start', () async {
      final rec = FakePcmRecorder();
      final input = RecordAudioInput(rec)
        ..useProfile(CaptureProfile.speechOutput);
      final states = StreamController<VoiceState>.broadcast(sync: true);
      final follower = CaptureProfileFollower(input, states.stream);
      final sub = input.start().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      states.add(VoiceState.listening);
      expect(input.profile, CaptureProfile.speechOutput, reason: 'läuft noch');
      await input.stop();
      await sub.cancel();
      final sub2 = input.start().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await input.stop();
      await sub2.cancel();
      expect(rec.profiles, [
        CaptureProfile.speechOutput,
        CaptureProfile.recognition,
      ]);
      await follower.dispose();
      await states.close();
    });

    test('ein späterer Wunsch nimmt den früheren zurück', () async {
      final rec = FakePcmRecorder();
      final input = RecordAudioInput(rec);
      final sub = input.start().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      input
        ..useProfile(CaptureProfile.speechOutput)
        ..useProfile(CaptureProfile.recognition);
      await input.stop();
      await sub.cancel();
      final sub2 = input.start().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await input.stop();
      await sub2.cancel();
      expect(rec.profiles, [
        CaptureProfile.recognition,
        CaptureProfile.recognition,
      ]);
    });
  });

  group('CaptureProfileFollower', () {
    late StreamController<VoiceState> states;
    late RecordAudioInput input;
    late List<String> log;
    late void Function(String) savedSink;

    setUp(() {
      states = StreamController<VoiceState>.broadcast(sync: true);
      input = RecordAudioInput(FakePcmRecorder());
      log = [];
      savedSink = voiceLogSink;
      voiceLogSink = log.add;
    });
    tearDown(() async {
      voiceLogSink = savedSink;
      await states.close();
    });

    test('nur während der Sprachausgabe die Quelle „Sprachausgabe“', () async {
      final follower = CaptureProfileFollower(input, states.stream);
      for (final s in [
        VoiceState.listening,
        VoiceState.transcribing,
        VoiceState.thinking,
      ]) {
        states.add(s);
        expect(input.profile, CaptureProfile.recognition, reason: '$s');
      }
      states.add(VoiceState.speaking);
      expect(input.profile, CaptureProfile.speechOutput);
      states.add(VoiceState.thinking);
      expect(input.profile, CaptureProfile.recognition);
      states.add(VoiceState.speaking);
      states.add(VoiceState.listening); // follow-up window after the answer
      expect(
        input.profile,
        CaptureProfile.recognition,
        reason: 'die eigentliche Anfrage nimmt wieder VOICE_RECOGNITION auf',
      );
      expect(
        log.where((l) => l.contains('audio-source')),
        hasLength(4),
        reason: 'zwei Wechsel hin, zwei zurück',
      );
      await follower.dispose();
    });

    test('läuft die Aufnahme, wird die Quelle nicht umgeschaltet', () async {
      final follower = CaptureProfileFollower(input, states.stream);
      final sub = input.start().listen((_) {});
      states.add(VoiceState.speaking);
      expect(input.profile, CaptureProfile.recognition);
      expect(log.where((l) => l.contains('applied')), hasLength(1));
      await input.stop();
      await sub.cancel();
      await follower.dispose();
    });

    test('dispose stellt die Erkennungsquelle her und hört auf', () async {
      final follower = CaptureProfileFollower(input, states.stream);
      states.add(VoiceState.speaking);
      expect(input.profile, CaptureProfile.speechOutput);
      await follower.dispose();
      expect(input.profile, CaptureProfile.recognition);
      states.add(VoiceState.speaking);
      expect(input.profile, CaptureProfile.recognition);
    });
  });
}
