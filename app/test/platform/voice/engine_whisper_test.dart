// B14 (Gerätetest 2026-10-13): whisper-small ≈ 1,3 GB PSS. At most one
// Whisper per process: the overlay uses the app's model, a model change
// frees the old one first, idle in the background frees it (WP30).

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/hint_term_providers.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/platform/channel_memory_trim.dart';
import 'package:wendelin/platform/voice/engine_whisper.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/sherpa_tts.dart';
import 'package:wendelin/platform/voice/whisper_stt.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../support/test_env.dart';

/// Loaded fake models of the „process“ (all engines of a test).
final class FakeProcess {
  final live = <FakeBackend>[];
  final events = <String>[];
  int loads = 0;
  Duration loadTime = Duration.zero;
  Duration freeTime = Duration.zero;

  Future<WhisperBackend> load(String modelId) async {
    loads++;
    events.add('load $modelId');
    await Future<void>.delayed(loadTime);
    final b = FakeBackend(this, modelId);
    live.add(b);
    events.add('loaded $modelId');
    return b;
  }
}

final class FakeBackend implements WhisperBackend {
  FakeBackend(this.process, this.modelId);

  final FakeProcess process;
  final String modelId;
  bool disposed = false;
  int calls = 0;

  @override
  Future<WhisperResult> transcribe(
    Float32List samples, {
    String? language,
  }) async {
    if (disposed) throw StateError('freigegeben');
    calls++;
    return WhisperResult(text: 'ok $modelId', language: 'de');
  }

  @override
  Future<void> dispose() async {
    process.events.add('free $modelId');
    await Future<void>.delayed(process.freeTime);
    disposed = true;
    process.live.remove(this);
    process.events.add('freed $modelId');
  }
}

/// [WhisperDirectory] of the fake process. A model whose engine ended
/// without withdrawing it ([gone]) does not answer any more.
final class FakeDirectory implements WhisperDirectory {
  FakeDirectory(this.process);

  final FakeProcess process;
  final published = <String, WhisperBackend>{};
  final gone = <WhisperBackend>{};

  @override
  Future<WhisperBackend?> lookup(String modelId) async {
    final b = published[modelId];
    if (b == null || gone.contains(b)) return null;
    return _Remote(this, b);
  }

  @override
  void publish(String modelId, WhisperBackend backend) =>
      published[modelId] = backend;

  @override
  void withdraw(String modelId, WhisperBackend backend) {
    if (identical(published[modelId], backend)) published.remove(modelId);
  }

  @override
  int liveModels() => process.live.length;
}

final class _Remote implements WhisperBackend {
  _Remote(this.dir, this.owner);

  final FakeDirectory dir;
  final WhisperBackend owner;

  @override
  Future<WhisperResult> transcribe(
    Float32List samples, {
    String? language,
  }) async {
    if (dir.gone.contains(owner) || (owner as FakeBackend).disposed) {
      throw const VoiceException(VoiceErrorKind.unavailable, 'weg');
    }
    return owner.transcribe(samples, language: language);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  final lines = <String>[];
  late void Function(String) savedSink;
  setUp(() {
    lines.clear();
    savedSink = voiceLogSink;
    voiceLogSink = lines.add;
  });
  tearDown(() => voiceLogSink = savedSink);

  final samples = Float32List(1600);

  group('EngineWhisper', () {
    late FakeProcess process;
    late FakeDirectory dir;
    setUp(() {
      process = FakeProcess();
      dir = FakeDirectory(process);
    });

    EngineWhisper engine(String id) => EngineWhisper(
      modelId: id,
      load: () => process.load(id),
      directory: dir,
      countLive: true,
    );

    test('zwei Engines (App, Overlay): ein Modell, geteilt', () async {
      final app = engine('whisper-small');
      final overlay = engine('whisper-small');
      await app.warm();
      await overlay.warm();
      expect(process.live, hasLength(1));
      expect(app.ownsModel, isTrue);
      expect(overlay.ownsModel, isFalse);
      final r = await overlay.transcribe(samples, language: 'de');
      expect(r.text, 'ok whisper-small');
      expect(process.live.single.calls, 1);
      expect(lines.where((l) => l.contains(' model-load ')), hasLength(1));
      expect(lines.any((l) => l.contains(' model-share ')), isTrue);
      expect(
        lines.singleWhere((l) => l.contains(' model-load ')),
        contains('live=1'),
      );
    });

    test('gleichzeitiges Vorwärmen lädt nur einmal', () async {
      final app = engine('whisper-small');
      await Future.wait([app.warm(), app.warm(), app.warm()]);
      expect(process.loads, 1);
    });

    test('Besitzer endet ohne Freigabe: der andere übernimmt', () async {
      final app = engine('whisper-small');
      final overlay = engine('whisper-small');
      await overlay.warm(); // overlay first: it owns the model
      await app.warm();
      expect(process.live, hasLength(1));
      // The overlay engine ends without withdrawing its model: it is still
      // listed but no longer answers.
      final owner = process.live.single..disposed = true;
      process.live.remove(owner);
      final r = await app.transcribe(samples, language: 'de');
      expect(r.text, 'ok whisper-small');
      expect(app.ownsModel, isTrue);
      expect(process.live, hasLength(1));
      expect(lines.any((l) => l.contains(' model-owner-gone ')), isTrue);
    });

    test('Freigabe: Modell weg, nächste Nutzung lädt neu', () async {
      final app = engine('whisper-base');
      await app.warm();
      await app.release(reason: 'idle');
      expect(process.live, isEmpty);
      expect(dir.published, isEmpty);
      expect(
        lines.singleWhere((l) => l.contains(' model-free ')),
        allOf(contains('reason=idle'), contains('live=0')),
      );
      await app.transcribe(samples);
      expect(process.loads, 2);
      expect(process.live, hasLength(1));
    });

    test('Modellwechsel: das alte ist frei, bevor das neue lädt', () async {
      process.freeTime = const Duration(milliseconds: 30);
      final base = engine('whisper-base');
      await base.warm();
      unawaited(base.release(reason: 'replaced'));
      final small = engine('whisper-small');
      await small.warm();
      expect(process.events, [
        'load whisper-base',
        'loaded whisper-base',
        'free whisper-base',
        'freed whisper-base',
        'load whisper-small',
        'loaded whisper-small',
      ]);
      expect(process.live.single.modelId, 'whisper-small');
    });

    test('Freigabe während des Ladens: wird gleich wieder frei', () async {
      process.loadTime = const Duration(milliseconds: 20);
      final app = engine('whisper-base');
      final warming = app.warm();
      await app.release();
      await expectLater(warming, throwsA(isA<VoiceException>()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(process.live, isEmpty);
    });
  });

  group('Provider (zwei Container = App und Overlay)', () {
    late FakeProcess process;
    late FakeDirectory dir;
    late _FakeTrim trim;
    setUp(() {
      process = FakeProcess();
      dir = FakeDirectory(process);
      trim = _FakeTrim();
    });

    ProviderContainer engineContainer({
      String model = 'whisper-small',
      Duration releaseDelay = const Duration(minutes: 2),
      List<Override> extra = const [],
      bool keep = false,
      Set<String> installedModels = const {},
    }) {
      final env = TestEnv(
        extraOverrides: [
          ...extra,
          whisperLoaderProvider.overrideWithValue((m, _) => process.load(m.id)),
          whisperDirectoryProvider.overrideWithValue(dir),
          memoryTrimSourceProvider.overrideWithValue(trim),
          voiceActivityDetectorProvider.overrideWith(
            (ref) async => FakeVoiceActivityDetector(),
          ),
          voiceReleaseDelayProvider.overrideWithValue(releaseDelay),
        ],
      );
      env.speechModels.installed.addAll({
        'whisper-base',
        'whisper-small',
        SpeechModelCatalog.sileroVad.id,
        ...installedModels,
      });
      unawaited(
        env.storage.settings.set(
          voiceSettingsKey,
          VoiceSettings(sttModel: model, keepModelLoaded: keep),
        ),
      );
      return env.container();
    }

    // Condition instead of wall-clock waiting: yields to the event loop
    // until [cond] holds (bounded, so a real defect still fails).
    Future<void> untilTrue(bool Function() cond) async {
      for (var i = 0; i < 5000 && !cond(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    test('App und Overlay: genau ein Whisper', () async {
      final app = engineContainer();
      final overlay = engineContainer();
      addTearDown(app.dispose);
      addTearDown(overlay.dispose);
      await app.read(voiceComponentsProvider.future);
      final o = await overlay.read(voiceComponentsProvider.future);
      expect(process.live, hasLength(1));
      final t = await o.stt.transcribe(
        AudioFrames.pattern('S' * 20)
            .reduce((a, b) => Int16List.fromList([...a, ...b])),
        language: 'de',
      );
      expect(t.text, 'ok whisper-small');
      expect(process.live, hasLength(1));
    });

    test('Modellwechsel: danach genau ein Whisper (das neue)', () async {
      final app = engineContainer(model: 'whisper-base');
      addTearDown(app.dispose);
      await app.read(speechToTextProvider.future);
      expect(process.live.single.modelId, 'whisper-base');
      await app
          .read(voiceSettingsProvider.notifier)
          .change((s) => s.copyWith(sttModel: 'whisper-small'));
      await app.read(speechToTextProvider.future);
      await untilTrue(
        () =>
            process.live.length == 1 &&
            process.live.single.modelId == 'whisper-small',
      );
      expect(process.live.single.modelId, 'whisper-small');
      expect(
        process.events.indexOf('freed whisper-base'),
        lessThan(process.events.indexOf('load whisper-small')),
      );
    });

    test(
      'im Hintergrund nach der Frist: 0 Whisper, Vorwärmen lädt neu',
      () async {
        final app = engineContainer(releaseDelay: Duration.zero);
        addTearDown(app.dispose);
        await app.read(activeVoiceProvider.future);
        final voice = app.read(voiceControllerProvider.notifier);
        expect(process.live, hasLength(1));
        await voice.background();
        // Zero deadline: the timer is event-driven, no wall clock involved.
        await untilTrue(() => process.live.isEmpty);
        expect(process.live, isEmpty);
        expect(
          lines.any(
            (l) => l.contains(' release ') && l.contains('reason=idle'),
          ),
          isTrue,
        );
        app.read(modelStatesProvider); // installed models known
        await untilTrue(() => app.read(voiceReadyProvider));
        voice.prewarm();
        await untilTrue(() => process.live.length == 1);
        expect(process.live, hasLength(1));
      },
    );

    test('Rückkehr vor der Frist: nichts wird freigegeben', () async {
      final app = engineContainer(releaseDelay: Duration.zero);
      addTearDown(app.dispose);
      await app.read(activeVoiceProvider.future);
      final voice = app.read(voiceControllerProvider.notifier);
      await voice.background();
      // Back before the (zero) deadline expires: prewarm cancels the timer.
      voice.prewarm();
      await pumpEventQueue();
      expect(process.live, hasLength(1));
    });

    test(
      'zurück, während background() noch wartet: nichts wird freigegeben',
      () async {
        final app = engineContainer(releaseDelay: Duration.zero);
        addTearDown(app.dispose);
        await app.read(activeVoiceProvider.future);
        final voice = app.read(voiceControllerProvider.notifier);
        // The release timer is armed after suspend(); the screen is back
        // before that (only `_foreground` stops the release then).
        final going = voice.background();
        voice.prewarm();
        await going;
        await pumpEventQueue();
        expect(process.live, hasLength(1));
        expect(lines.where((l) => l.contains(' release ')), isEmpty);
      },
    );

    test('Freigabe gibt auch die Offline-Stimme frei', () async {
      final synth = _CountingSynthesizer();
      final app = engineContainer(
        extra: [sherpaSynthesizerProvider.overrideWithValue(synth)],
      );
      addTearDown(app.dispose);
      await app.read(activeVoiceProvider.future);
      await app
          .read(voiceControllerProvider.notifier)
          .releaseModels(reason: 'idle');
      expect(process.live, isEmpty);
      expect(synth.disposed, 1);
    });

    group('Hinweis-Begriffe', () {
      final names = NotifierProvider<_Names, List<String>>(_Names.new);

      ProviderContainer withNames(String model) => engineContainer(
        model: model,
        installedModels: {SpeechModelCatalog.parakeetV3.id},
        extra: [hintTermsProvider.overrideWith((ref) => ref.watch(names))],
      );

      test('Modell mit Hotwords: neue Namen bauen den Erkenner neu', () async {
        final app = withNames(SpeechModelCatalog.parakeetV3.id);
        addTearDown(app.dispose);
        await app.read(speechToTextProvider.future);
        expect(
          process.events.where((e) => e.startsWith('load ')),
          hasLength(1),
        );
        app.read(names.notifier).set(['Wendelin', 'Küche']);
        await pumpEventQueue();
        await app.read(speechToTextProvider.future);
        await untilTrue(
          () => process.events.where((e) => e.startsWith('load ')).length == 2,
        );
        expect(
          process.events.where((e) => e.startsWith('load ')),
          hasLength(2),
        );
        expect(process.live, hasLength(1));
      });

      test('Whisper ignoriert die Namen: kein Neuladen', () async {
        final app = withNames('whisper-small');
        addTearDown(app.dispose);
        await app.read(speechToTextProvider.future);
        app.read(names.notifier).set(['Wendelin', 'Küche']);
        await pumpEventQueue();
        await app.read(speechToTextProvider.future);
        await pumpEventQueue();
        expect(
          process.events.where((e) => e.startsWith('load ')),
          hasLength(1),
        );
      });

      test('Engine-Name kommt aus dem Katalog', () async {
        final app = withNames(SpeechModelCatalog.parakeetV3.id);
        addTearDown(app.dispose);
        final stt = await app.read(speechToTextProvider.future);
        expect(stt.info.name, contains('Parakeet'));
        expect(stt.info.model, SpeechModelCatalog.parakeetV3.id);
      });
    });

    group('Modell im Speicher halten', () {
      Future<(ProviderContainer, _CountingSynthesizer)> loaded({
        required bool keep,
      }) async {
        final synth = _CountingSynthesizer();
        final app = engineContainer(
          keep: keep,
          releaseDelay: Duration.zero,
          extra: [sherpaSynthesizerProvider.overrideWithValue(synth)],
        );
        addTearDown(app.dispose);
        await app.read(activeVoiceProvider.future);
        await app.read(voiceSettingsProvider.future);
        app.read(voiceControllerProvider); // alive, like in the app
        expect(process.live, hasLength(1));
        return (app, synth);
      }

      test('an: Hintergrund und Overlay-Ende geben nichts frei', () async {
        final (app, synth) = await loaded(keep: true);
        final voice = app.read(voiceControllerProvider.notifier);
        await voice.background();
        await voice.releaseModels(reason: 'overlay-close');
        await voice.releaseModels(reason: 'idle');
        await pumpEventQueue();
        expect(process.live, hasLength(1));
        expect(synth.disposed, 0);
        expect(
          lines.where((l) => l.contains('release-skipped')),
          contains(contains('reason=overlay-close')),
        );
      });

      test('aus: Overlay-Ende gibt STT und Stimme frei', () async {
        final (app, synth) = await loaded(keep: false);
        await app
            .read(voiceControllerProvider.notifier)
            .releaseModels(reason: 'overlay-close');
        expect(process.live, isEmpty);
        expect(synth.disposed, 1);
      });

      test(
        'an: Speicherdruck (onTrimMemory 15) gibt STT und TTS frei',
        () async {
          final (app, synth) = await loaded(keep: true);
          trim.add(15);
          await untilTrue(() => process.live.isEmpty);
          expect(process.live, isEmpty);
          expect(synth.disposed, 1);
          expect(
            lines.any(
              (l) => l.contains(' release ') && l.contains('reason=memory'),
            ),
            isTrue,
          );
          expect(app.read(voiceControllerProvider).active, isFalse);
        },
      );

      test(
        'Speicherdruck während einer laufenden Anfrage gibt nichts frei',
        () async {
          final (app, synth) = await loaded(keep: true);
          final agent = app.read(agentControllerProvider.notifier);
          agent.seed(app.read(agentControllerProvider).copyWith(running: true));
          trim.add(15);
          await pumpEventQueue();
          expect(process.live, hasLength(1));
          expect(synth.disposed, 0);
          // Die Anfrage endet, der nächste Druck gibt frei.
          agent.seed(
            app.read(agentControllerProvider).copyWith(running: false),
          );
          trim.add(15);
          await untilTrue(() => process.live.isEmpty);
          expect(process.live, isEmpty);
        },
      );

      test(
        'Speicherdruck bei laufender Sprachsitzung gibt nichts frei',
        () async {
          final (app, synth) = await loaded(keep: true);
          final voice = app.read(voiceControllerProvider.notifier);
          voice.seed(
            app.read(voiceControllerProvider).copyWith(awaitingAnswer: true),
          );
          trim.add(15);
          await pumpEventQueue();
          expect(process.live, hasLength(1));
          expect(synth.disposed, 0);
        },
      );

      test('aus: Speicherdruck gibt ebenfalls frei', () async {
        await loaded(keep: false);
        trim.add(40);
        await untilTrue(() => process.live.isEmpty);
        expect(process.live, isEmpty);
      });

      test(
        'UI_HIDDEN (20) und schwache Stufen sind kein Speicherdruck',
        () async {
          final (_, synth) = await loaded(keep: true);
          trim
            ..add(20)
            ..add(5)
            ..add(10);
          await pumpEventQueue();
          expect(process.live, hasLength(1));
          expect(synth.disposed, 0);
        },
      );
    });

    test('Besitzer (App) wird geschlossen: Overlay lädt eigenes', () async {
      final app = engineContainer();
      final overlay = engineContainer();
      addTearDown(overlay.dispose);
      await app.read(voiceComponentsProvider.future);
      final o = await overlay.read(voiceComponentsProvider.future);
      app.dispose();
      await untilTrue(() => process.live.isEmpty);
      expect(process.live, isEmpty);
      final t = await o.stt.transcribe(
        AudioFrames.pattern('S' * 20)
            .reduce((a, b) => Int16List.fromList([...a, ...b])),
      );
      expect(t.text, 'ok whisper-small');
      expect(process.live, hasLength(1));
    });
  });
}

/// Offline voices that count [dispose].
final class _CountingSynthesizer implements SpeechSynthesizer {
  int disposed = 0;

  @override
  Future<Wav> synthesize(
    String text, {
    required String voiceId,
    double speed = 1.0,
  }) => throw UnimplementedError();

  @override
  Future<void> dispose() async => disposed++;
}

final class _Names extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void set(List<String> v) => state = v;
}

/// Android `onTrimMemory` levels pushed by the test.
final class _FakeTrim implements MemoryTrimSource {
  final _c = StreamController<int>.broadcast();

  void add(int level) => _c.add(level);

  @override
  Stream<int> get levels => _c.stream;
}
