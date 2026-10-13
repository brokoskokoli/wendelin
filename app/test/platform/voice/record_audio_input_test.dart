import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/record_audio_input.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../support/fake_microphone.dart';

Matcher _kind(VoiceErrorKind k) =>
    isA<VoiceException>().having((e) => e.kind, 'kind', k);

void main() {
  audioInputContract(
    () => RecordAudioInput(FakePcmRecorder()),
    name: 'RecordAudioInput (Attrappe)',
  );

  test(
    'Frames sind 16-bit-Samples, ungerade Chunks werden zusammengesetzt',
    () async {
      final rec = FakePcmRecorder(chunk: 641);
      final input = RecordAudioInput(rec);
      final frames = <Int16List>[];
      final sub = input.start().listen(frames.add);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await input.stop();
      await sub.cancel();
      final samples = frames.fold(0, (n, f) => n + f.length);
      expect(samples, greaterThan(300));
      expect(frames.first.first, 0x0100); // bytes 00 01 → 0x0100
      expect(rec.requests, everyElement(isFalse)); // never asks itself
    },
  );

  test('ohne Berechtigung: permissionDenied auf dem Stream', () async {
    final input = RecordAudioInput(FakePcmRecorder(granted: false));
    await expectLater(
      input.start(),
      emitsError(_kind(VoiceErrorKind.permissionDenied)),
    );
    expect(input.isRunning, isFalse);
  });

  test('Plattformfehler beim Start: unavailable', () async {
    final rec = FakePcmRecorder()..startError = PlatformException(code: 'busy');
    final input = RecordAudioInput(rec);
    await expectLater(
      input.start(),
      emitsError(_kind(VoiceErrorKind.unavailable)),
    );
    expect(input.isRunning, isFalse);
  });

  test('Fehler im Stream: unavailable, danach Ende', () async {
    final rec = FakePcmRecorder();
    final input = RecordAudioInput(rec);
    final events = <Object>[];
    final done = Completer<void>();
    input.start().listen((_) {}, onError: events.add, onDone: done.complete);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await rec.endFromPlatform(error: StateError('weg'));
    await done.future;
    expect(events.single, _kind(VoiceErrorKind.unavailable));
    expect(input.isRunning, isFalse);
  });

  test('Plattform beendet den Stream: Aufnahme endet', () async {
    final rec = FakePcmRecorder();
    final input = RecordAudioInput(rec);
    final done = Completer<void>();
    input.start().listen((_) {}, onDone: done.complete);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await rec.endFromPlatform();
    await done.future;
    expect(input.isRunning, isFalse);
  });

  test('stop direkt nach start: Recorder wird wieder gestoppt', () async {
    final rec = FakePcmRecorder();
    final input = RecordAudioInput(rec);
    final done = Completer<void>();
    input.start().listen((_) {}, onDone: done.complete);
    await input.stop();
    await done.future;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(rec.running, isFalse);
    expect(input.isRunning, isFalse);
  });
}
