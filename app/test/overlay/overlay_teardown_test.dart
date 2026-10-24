// WP145: the overlay engine ends without disposing its ProviderContainer, so
// no `ref.onDispose` ran and native objects stayed open behind every overlay
// (Native Heap +4 MB per opening). `tearDownOverlayEngine` frees them on
// close. Counting fakes stand in for the native objects.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/core_providers.dart';
import 'package:wendelin/di/dispose_tracker.dart';
import 'package:wendelin/di/speaker_providers.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/di/wake_settings.dart';
import 'package:wendelin/platform/channel_memory_trim.dart';
import 'package:wendelin/platform/voice/engine_whisper.dart';
import 'package:wendelin/platform/voice/whisper_stt.dart';
import 'package:wendelin/ui/overlay/overlay_teardown.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';

/// Native objects of the „process“: opened and freed are counted per kind.
final class Counts {
  final opened = <String, int>{};
  final freed = <String, int>{};

  void open(String kind) => opened[kind] = (opened[kind] ?? 0) + 1;
  void free(String kind) => freed[kind] = (freed[kind] ?? 0) + 1;
  int live(String kind) => (opened[kind] ?? 0) - (freed[kind] ?? 0);
}

final class _Backend implements WhisperBackend {
  _Backend(this.counts) {
    counts.open('whisper');
  }
  final Counts counts;

  @override
  Future<WhisperResult> transcribe(
    Float32List samples, {
    String? language,
  }) async => const WhisperResult(text: 'ok', language: 'de');

  @override
  Future<void> dispose() async => counts.free('whisper');
}

final class _NoDirectory implements WhisperDirectory {
  @override
  Future<WhisperBackend?> lookup(String modelId) async => null;
  @override
  void publish(String modelId, WhisperBackend backend) {}
  @override
  void withdraw(String modelId, WhisperBackend backend) {}
  @override
  int liveModels() => 0;
}

/// Directory that records what is published (nothing may be after a close).
final class _RecordingDirectory implements WhisperDirectory {
  _RecordingDirectory({this.lookupGate});
  final Completer<void>? lookupGate;
  final published = <String>[];
  @override
  Future<WhisperBackend?> lookup(String modelId) async {
    await lookupGate?.future;
    return null;
  }

  @override
  void publish(String modelId, WhisperBackend backend) =>
      published.add(modelId);
  @override
  void withdraw(String modelId, WhisperBackend backend) {}
  @override
  int liveModels() => 0;
}

final class _Vad implements VoiceActivityDetector {
  @override
  double get threshold => 0.5;
  @override
  double speechProbability(Int16List frame) => 0;
  @override
  void reset() {}
}

/// The ORT chain of the barge-in detector (mel, embedding, classifier).
final class _Chain implements WakeFeatureExtractor {
  _Chain(this.counts) {
    counts.open('ort-chain');
  }
  final Counts counts;
  bool _closed = false;

  @override
  String get featureVersion => 'fake-1';
  @override
  Float32List? get embeddingMean => null;
  @override
  String? get centerId => null;
  @override
  Future<void> open() async {}
  @override
  Future<List<WakeWindow>> accept(Int16List frame) async => const [];
  @override
  void reset() {}

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    counts.free('ort-chain');
  }
}

final class _FakeTrim implements MemoryTrimSource {
  @override
  Stream<int> get levels => const Stream.empty();
}

void main() {
  late Counts counts;
  setUp(() => counts = Counts());

  /// An overlay engine as `assistantMain` builds it, native objects counted.
  ProviderContainer overlayEngine({required bool keep}) {
    final env = TestEnv(
      extraOverrides: [
        whisperLoaderProvider.overrideWithValue(
          (m, _) async => _Backend(counts),
        ),
        whisperDirectoryProvider.overrideWithValue(_NoDirectory()),
        memoryTrimSourceProvider.overrideWithValue(_FakeTrim()),
        sileroOpenerProvider.overrideWithValue((path, threshold) {
          counts.open('silero');
          return (vad: _Vad(), dispose: () => counts.free('silero'));
        }),
        wakeFeaturesFactoryProvider.overrideWithValue(() => _Chain(counts)),
        audioInputProvider.overrideWithValue(
          FakeAudioInput(
            frames: [for (var i = 0; i < 4; i++) Int16List(480)],
            frameInterval: const Duration(milliseconds: 1),
          ),
        ),
      ],
    );
    env.speechModels.installed.addAll({
      'whisper-base',
      SpeechModelCatalog.sileroVad.id,
    });
    unawaited(
      env.storage.settings.set(
        voiceSettingsKey,
        VoiceSettings(
          sttModel: 'whisper-base',
          keepModelLoaded: keep,
          conversationMode: true,
        ),
      ),
    );
    return env.container();
  }

  /// One overlay: opens Whisper, Silero and the barge-in chain, then closes
  /// like `_close` does: releaseModels, then the teardown.
  Future<WendelinStorage> useAndClose(ProviderContainer c) async {
    final comps = (await c.read(activeVoiceProvider.future))!;
    comps.vad.speechProbability(Int16List(512));
    await comps.stt.transcribe(Int16List(1600), language: 'de');
    final store = c.read(wakeStoreProvider);
    await store.saveSpeakers([const WakeSpeaker(id: 'a', name: 'Anna')]);
    await store.save(
      WakeTemplates(
        speakerId: 'a',
        featureVersion: 'fake-1',
        threshold: 0.5,
        embeddings: [Float32List(4)],
        center: wakeCenterId,
      ),
    );
    final barge = c.read(wakeBargeInDetectorProvider)!;
    await barge.start();
    await barge.stop();
    await c
        .read(voiceControllerProvider.notifier)
        .releaseModels(reason: 'overlay-close');
    final storage = c.read(storageProvider);
    await tearDownOverlayEngine(c);
    return storage;
  }

  for (final keep in [false, true]) {
    test('sechs Overlay-Zyklen, keepModelLoaded=$keep: jede native Ressource '
        'ist nach dem Schließen frei', () async {
      for (var cycle = 0; cycle < 6; cycle++) {
        final c = overlayEngine(keep: keep);
        final storage = await useAndClose(c);
        for (final kind in ['whisper', 'silero', 'ort-chain']) {
          expect(counts.live(kind), 0, reason: 'Zyklus $cycle: $kind offen');
        }
        // The database connection is closed: no query goes through.
        await expectLater(
          storage.settings.get(voiceSettingsKey),
          throwsA(anything),
          reason: 'Zyklus $cycle: Datenbank offen',
        );
      }
      for (final kind in ['whisper', 'silero', 'ort-chain']) {
        expect(counts.opened[kind], 6, reason: '$kind je Zyklus einmal');
        expect(counts.freed[kind], 6, reason: '$kind je Zyklus einmal frei');
      }
    });
  }

  test('ohne Teardown (Stand vor WP145) bleibt Whisper bei keepModelLoaded '
      'und die Barge-in-Kette offen', () async {
    final c = overlayEngine(keep: true);
    final comps = (await c.read(activeVoiceProvider.future))!;
    await comps.stt.transcribe(Int16List(1600), language: 'de');
    await c
        .read(voiceControllerProvider.notifier)
        .releaseModels(reason: 'overlay-close');
    expect(counts.live('whisper'), 1, reason: 'Befund: Whisper bleibt');
    await tearDownOverlayEngine(c);
    expect(counts.live('whisper'), 0);
  });

  // Real providers whose native object is not countable with a fake (worker
  // isolate, plugin): each reports its free to the tracker when disposed.
  final tracked = <String, Object? Function(ProviderContainer)>{
    'sherpa-synthesizer': (c) => c.read(sherpaSynthesizerProvider),
    'speaker-embedder': (c) => c.read(speakerEmbedderProvider),
    'wake-confirm-tone': (c) => c.read(wakeConfirmToneProvider),
    'wake-prompt-tone': (c) => c.read(wakePromptToneProvider),
    'sherpa-tts-playback': (c) =>
        c.read(Provider<TextToSpeech>(createSherpaTts)),
  };
  for (final entry in tracked.entries) {
    test('${entry.key}: Freigeben läuft über den Tracker', () async {
      final c = overlayEngine(keep: false);
      final tracker = c.read(disposeTrackerProvider);
      entry.value(c);
      final before = tracker.tracked;
      c.dispose();
      // sherpa-tts-playback also holds the synthesizer: at least one.
      expect(tracker.tracked, greaterThan(before), reason: entry.key);
      await tracker.drain();
      expect(tracker.pending, 0);
    });
  }

  test('Teardown bricht nach dem Budget ab und wirft nicht', () async {
    final c = overlayEngine(keep: false);
    final tracker = c.read(disposeTrackerProvider);
    final hang = Completer<void>();
    tracker.track(hang.future);
    await tearDownOverlayEngine(c, budget: const Duration(milliseconds: 20));
    expect(tracker.pending, 1, reason: 'der hängende Schritt blockiert nicht');
    hang.complete();
    await tracker.drain();
    expect(tracker.pending, 0);
  });

  // Bug (also on main): the overlay closed while Whisper was still loading;
  // the load finished in an engine that was gone and the ~400 MB stayed.
  group('Schließen während Whisper noch lädt', () {
    test('Teardown hält Android, wartet auf das Ladeende: genau ein Free, '
        'nichts veröffentlicht', () async {
      final started = Completer<void>();
      final gate = Completer<void>();
      final dir = _RecordingDirectory();
      final env = TestEnv(
        extraOverrides: [
          whisperLoaderProvider.overrideWithValue((m, _) async {
            started.complete();
            await gate.future;
            return _Backend(counts);
          }),
          whisperDirectoryProvider.overrideWithValue(dir),
          memoryTrimSourceProvider.overrideWithValue(_FakeTrim()),
        ],
      );
      env.speechModels.installed.add('whisper-base');
      unawaited(
        env.storage.settings.set(
          voiceSettingsKey,
          const VoiceSettings(sttModel: 'whisper-base'),
        ),
      );
      final c = env.container();
      unawaited(
        c
            .read(engineWhisperProvider.future)
            .then<Object?>((_) => null, onError: (_) => null),
      );
      await started.future;
      var held = 0;
      await tearDownOverlayEngine(
        c,
        budget: const Duration(milliseconds: 20),
        hold: () async {
          held++;
          gate.complete(); // the load ends while Android waits
        },
      );
      expect(held, 1, reason: 'Android wurde gebeten zu warten');
      expect(counts.opened['whisper'], 1);
      expect(
        counts.freed['whisper'],
        1,
        reason: 'genau ein Free nach Ladeende',
      );
      expect(
        dir.published,
        isEmpty,
        reason: 'nichts prozessweit veröffentlicht',
      );
    });

    test('Schließen vor dem Lookup: es wird gar nicht erst geladen', () async {
      final gate = Completer<void>();
      final dir = _RecordingDirectory(lookupGate: gate);
      var loads = 0;
      final whisper = EngineWhisper(
        modelId: 'whisper-base',
        load: () async {
          loads++;
          return _Backend(counts);
        },
        directory: dir,
        countLive: false,
      );
      final warm = whisper.warm().then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      final release = whisper.release();
      gate.complete();
      await release;
      expect(await warm, isA<VoiceException>());
      expect(loads, 0);
      expect(dir.published, isEmpty);
    });

    test('release wartet auf das laufende Laden und gibt es frei', () async {
      final gate = Completer<void>();
      final dir = _RecordingDirectory();
      final whisper = EngineWhisper(
        modelId: 'whisper-base',
        load: () async {
          await gate.future;
          return _Backend(counts);
        },
        directory: dir,
        countLive: false,
      );
      unawaited(whisper.warm().catchError((_) {}));
      await pumpEventQueue();
      var released = false;
      final release = whisper.release().then((_) => released = true);
      await pumpEventQueue();
      expect(released, isFalse, reason: 'wartet auf das Ladeende');
      gate.complete();
      await release;
      expect(counts.live('whisper'), 0);
      expect(counts.freed['whisper'], 1);
      expect(dir.published, isEmpty);
    });
  });
}
