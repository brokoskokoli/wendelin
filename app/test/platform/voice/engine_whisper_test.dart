// B14 (Gerätetest 2026-10-13): whisper-small ≈ 1,3 GB PSS. At most one
// Whisper per process: the overlay uses the app's model, a model change
// frees the old one first, idle in the background frees it (WP30).

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/hint_term_providers.dart';
import 'package:wendelin/di/speaker_providers.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/platform/channel_memory_trim.dart';
import 'package:wendelin/platform/voice/engine_whisper.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/sherpa_tts.dart';
import 'package:wendelin/platform/voice/whisper_stt.dart';
import 'package:wendelin/ui/overlay/overlay_teardown.dart';
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
final class FakeDirectory implements UsageAwareDirectory {
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

  final usage = <String, int>{};
  final watchers = <String, void Function()>{};

  @override
  Future<int> users(String modelId) async => usage[modelId] ?? 0;

  @override
  void markUse(String modelId) => usage[modelId] = (usage[modelId] ?? 0) + 1;

  @override
  void unmarkUse(String modelId) {
    usage[modelId] = (usage[modelId] ?? 1) - 1;
    watchers[modelId]?.call();
  }

  @override
  void watchUsers(String modelId, void Function() onLeft) =>
      watchers[modelId] = onLeft;

  @override
  void unwatchUsers(String modelId) => watchers.remove(modelId);
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

    test('Besitzer gibt frei, solange das Overlay das Modell nutzt: erst '
        'nach dem Overlay (WP146)', () async {
      final app = engine('whisper-small');
      final overlay = engine('whisper-small');
      await app.warm();
      await overlay.warm();
      await app.release(reason: 'idle');
      // The model stays: the overlay keeps using it, no second copy.
      expect(process.live, hasLength(1));
      expect(app.ownsModel, isTrue);
      expect(
        lines.singleWhere((l) => l.contains(' model-release-deferred ')),
        allOf(contains('users=1'), contains('reason=idle')),
      );
      final r = await overlay.transcribe(samples, language: 'de');
      expect(r.text, 'ok whisper-small');
      expect(process.loads, 1);
      // The overlay closes: the waiting release runs.
      await overlay.release(reason: 'overlay-close');
      await pumpEventQueue();
      expect(process.live, isEmpty);
      expect(app.ownsModel, isFalse);
      expect(
        lines.singleWhere((l) => l.contains(' model-free ')),
        contains('reason=idle'),
      );
    });

    test(
      'Engine-Ende (dispose) gibt immer frei, auch mit Nutzer (WP146)',
      () async {
        final app = engine('whisper-small');
        final overlay = engine('whisper-small');
        await app.warm();
        await overlay.warm();
        await app.dispose();
        expect(process.live, isEmpty);
      },
    );

    test('Neuaufbau (replaced) gibt nicht frei, solange das Overlay das Modell '
        'nutzt; erst nach ihm (WP146)', () async {
      final app = engine('whisper-small');
      final overlay = engine('whisper-small');
      await app.warm();
      await overlay.warm();
      await app.release(reason: 'replaced');
      expect(process.live, hasLength(1));
      final r = await overlay.transcribe(samples, language: 'de');
      expect(r.text, 'ok whisper-small');
      expect(process.loads, 1);
      expect(lines.any((l) => l.contains(' model-owner-gone ')), isFalse);
      await overlay.release(reason: 'overlay-close');
      await pumpEventQueue();
      expect(process.live, isEmpty);
      expect(
        lines.singleWhere((l) => l.contains(' model-free ')),
        contains('reason=replaced'),
      );
    });

    test(
      'Nutzung wieder aufgenommen: die wartende Freigabe entfällt (WP146)',
      () async {
        final app = engine('whisper-small');
        final overlay = engine('whisper-small');
        await app.warm();
        await overlay.warm();
        await app.release(reason: 'idle');
        await app.warm();
        await overlay.release();
        await pumpEventQueue();
        expect(process.live, hasLength(1));
        expect(app.ownsModel, isTrue);
      },
    );

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
      bool realVad = false,
    }) {
      final env = TestEnv(
        extraOverrides: [
          ...extra,
          whisperLoaderProvider.overrideWithValue((m, _) => process.load(m.id)),
          whisperDirectoryProvider.overrideWithValue(dir),
          memoryTrimSourceProvider.overrideWithValue(trim),
          if (!realVad)
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

    // The real wiring of voiceActivityDetectorProvider runs; only the
    // native Silero constructor is a counting fake (B14/WP143).
    for (final keep in [false, true]) {
      test('sechs Overlay-Zyklen, keepModelLoaded=$keep: höchstens ein Silero '
          'und ein Whisper', () async {
        var live = 0;
        var maxLive = 0;
        var loads = 0;
        var frees = 0;
        var warmFrames = 0;
        OpenedVad open(String path, double threshold) {
          loads++;
          maxLive = math.max(maxLive, ++live);
          return (
            vad: _CountingVad(() => warmFrames++),
            dispose: () {
              frees++;
              live--;
            },
          );
        }

        final app = engineContainer(
          model: 'whisper-base',
          keep: keep,
          extra: [sileroOpenerProvider.overrideWithValue(open)],
          realVad: true,
        );
        addTearDown(app.dispose);
        await app.read(voiceComponentsProvider.future);
        // The app's own Silero stays open (it is in use), count it.
        final appLive = live;
        expect(appLive, 1, reason: 'prewarm opens Silero');
        for (var cycle = 0; cycle < 6; cycle++) {
          final overlay = engineContainer(
            model: 'whisper-base',
            keep: keep,
            extra: [sileroOpenerProvider.overrideWithValue(open)],
            realVad: true,
          );
          // No addTearDown(dispose): the overlay engine ends without
          // disposing its container.
          final c = await overlay.read(activeVoiceProvider.future);
          c!.vad.speechProbability(Int16List(512));
          await overlay
              .read(voiceControllerProvider.notifier)
              .releaseModels(reason: 'overlay-close');
          expect(
            live,
            appLive,
            reason: 'Zyklus $cycle: Silero des Overlays frei',
          );
          expect(process.live, hasLength(1), reason: 'Zyklus $cycle');
        }
        expect(loads, 1 + 6);
        expect(frees, 6);
        expect(maxLive, 2, reason: 'App + ein Overlay, nie mehr');
        expect(process.loads, 1, reason: 'das Modell der App wird geteilt');
        expect(warmFrames, 6);
      });

      test('sechs Overlay-Zyklen mit eigenem Whisper, keep=$keep: höchstens '
          'ein Modell und ein Silero', () async {
        var live = 0;
        var maxLive = 0;
        var maxWhisper = 0;
        OpenedVad open(String path, double threshold) {
          maxLive = math.max(maxLive, ++live);
          return (vad: _CountingVad(() {}), dispose: () => live--);
        }

        for (var cycle = 0; cycle < 6; cycle++) {
          final overlay = engineContainer(
            model: 'whisper-small',
            keep: keep,
            extra: [sileroOpenerProvider.overrideWithValue(open)],
            realVad: true,
          );
          final c = await overlay.read(activeVoiceProvider.future);
          maxWhisper = math.max(maxWhisper, process.live.length);
          await c!.stt.transcribe(Int16List(1600), language: 'de');
          await overlay
              .read(voiceControllerProvider.notifier)
              .releaseModels(reason: 'overlay-close');
          expect(live, 0, reason: 'Zyklus $cycle: Silero frei');
          if (!keep) {
            expect(process.live, isEmpty, reason: 'Zyklus $cycle');
          }
        }
        expect(maxLive, 1);
        expect(maxWhisper, 1);
        expect(process.live.length, keep ? 1 : 0);
        if (!keep) {
          expect(process.loads, 6);
          expect(
            process.events.where((e) => e.startsWith('freed ')).length,
            process.loads,
          );
        } else {
          // Kept on purpose: the next overlay shares the kept model.
          expect(process.loads, 1);
        }
      });
    }

    test('warmUp öffnet Silero und Whisper nach release wieder', () async {
      var live = 0;
      OpenedVad open(String path, double threshold) {
        live++;
        return (vad: _CountingVad(() {}), dispose: () => live--);
      }

      final c = engineContainer(
        extra: [sileroOpenerProvider.overrideWithValue(open)],
        realVad: true,
      );
      addTearDown(c.dispose);
      final comps = (await c.read(activeVoiceProvider.future))!;
      expect(live, 1);
      await comps.release!();
      expect(live, 0);
      expect(process.live, isEmpty);
      await comps.warmUp!();
      expect(live, 1, reason: 'Silero wieder offen');
      expect(process.live, hasLength(1));
    });

    test('Neuaufbau des Providers, solange das Overlay das Modell nutzt: das '
        'Overlay behält es (WP146)', () async {
      final app = engineContainer(model: 'whisper-base');
      addTearDown(app.dispose);
      final overlay = engineContainer(model: 'whisper-base');
      addTearDown(overlay.dispose);
      await app.read(speechToTextProvider.future);
      final o = await overlay.read(voiceComponentsProvider.future);
      await app
          .read(voiceSettingsProvider.notifier)
          .change((s) => s.copyWith(sttModel: 'whisper-small'));
      await app.read(speechToTextProvider.future);
      await pumpEventQueue();
      final base = process.live.where((b) => b.modelId == 'whisper-base');
      expect(base, hasLength(1), reason: 'Overlay nutzt es noch');
      final loadsBefore = process.loads;
      final t = await o.stt.transcribe(
        AudioFrames.pattern('S' * 20)
            .reduce((a, b) => Int16List.fromList([...a, ...b])),
      );
      expect(t.text, 'ok whisper-base');
      expect(process.loads, loadsBefore, reason: 'kein eigenes Laden');
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

    test('Sprechererkennung: aus = kein Erkenner, an = Erkenner und Freigabe '
        'gibt das Sprechermodell frei', () async {
      final off = engineContainer();
      addTearDown(off.dispose);
      expect((await off.read(voiceComponentsProvider.future)).speaker, isNull);

      final embedder = FakeSpeakerEmbedder([]);
      final on = engineContainer(
        extra: [speakerEmbedderProvider.overrideWithValue(embedder)],
      );
      addTearDown(on.dispose);
      await on
          .read(voiceSettingsProvider.notifier)
          .change((s) => s.copyWith(speakerRecognition: true));
      final c = await on.read(voiceComponentsProvider.future);
      expect(c.speaker, isNotNull);
      await c.release!();
      expect(embedder.releases, 1);

      // Ohne Erkenner lädt die Freigabe nichts nach.
      final cOff = await off.read(voiceComponentsProvider.future);
      await cOff.release!();
    });

    test('Besitzer (App) wird geschlossen: Overlay lädt eigenes', () async {
      final app = engineContainer();
      final overlay = engineContainer();
      addTearDown(overlay.dispose);
      await app.read(voiceComponentsProvider.future);
      final o = await overlay.read(voiceComponentsProvider.future);
      // The engine of the owner ends (overlay teardown): frees at once.
      await tearDownOverlayEngine(app);
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

/// Detector fake that counts the frames it hears.
final class _CountingVad implements VoiceActivityDetector {
  _CountingVad(this.onFrame);
  final void Function() onFrame;
  @override
  double get threshold => 0.5;
  @override
  double speechProbability(Int16List frame) {
    onFrame();
    return 0;
  }

  @override
  void reset() {}
}
