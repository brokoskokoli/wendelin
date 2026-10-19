import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  test('aus (Standard): jeder Grund gibt frei', () {
    expect(const VoiceSettings().keepModelLoaded, isFalse);
    for (final r in [
      'idle',
      'overlay-close',
      'release',
      memoryPressureReason,
    ]) {
      expect(mayReleaseModels(r, keepLoaded: false), isTrue, reason: r);
    }
  });

  test('an: nur Speicherdruck gibt frei', () {
    expect(mayReleaseModels('idle', keepLoaded: true), isFalse);
    expect(mayReleaseModels('overlay-close', keepLoaded: true), isFalse);
    expect(mayReleaseModels(memoryPressureReason, keepLoaded: true), isTrue);
  });

  test('Einstellung: JSON, Gleichheit, Stationsmodus-Hook', () {
    const on = VoiceSettings(keepModelLoaded: true);
    expect(VoiceSettings.fromJson(on.toJson()).keepModelLoaded, isTrue);
    expect(on == const VoiceSettings(), isFalse);
    expect(on.hashCode == const VoiceSettings().hashCode, isFalse);
    expect(const VoiceSettings().withStationDefaults(), on);
    expect(
      VoiceSettings.fromJson({'keepModelLoaded': 'ja'}).keepModelLoaded,
      isFalse,
    );
  });

  test('STT-Modell aus dem Katalog bleibt erhalten, Unbekanntes nicht', () {
    for (final id in ['parakeet-tdt-0.6b-v3', 'canary-180m-flash']) {
      expect(VoiceSettings.fromJson({'sttModel': id}).sttModel, id);
    }
    expect(
      VoiceSettings.fromJson({'sttModel': 'silero-vad'}).sttModel,
      'whisper-small',
    );
    expect(
      VoiceSettings.fromJson({'sttModel': 'nix'}).sttModel,
      'whisper-small',
    );
  });

  test(
    'Speicherdruck: ab RUNNING_CRITICAL und Hintergrundstufen, nicht 20',
    () {
      for (final level in [15, 40, 60, 80]) {
        expect(isMemoryPressure(level), isTrue, reason: '$level');
      }
      for (final level in [0, 5, 10, 20]) {
        expect(isMemoryPressure(level), isFalse, reason: '$level');
      }
    },
  );
}
