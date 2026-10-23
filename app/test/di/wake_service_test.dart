import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/voice_settings_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/di/wake_service.dart';
import 'package:wendelin/platform/wake/wake_detector.dart';
import 'package:wendelin/platform/wake/wake_platform.dart';
import 'package:wendelin_storage/testing.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

final class _FakePlatform extends WakePlatform {
  WakeServiceStatus current = const WakeServiceStatus();

  Future<void>? gate;

  @override
  Future<WakeServiceStatus> status() async {
    final snapshot = current;
    await gate;
    return snapshot;
  }

  final sent = <({bool enabled, WakeCondition condition, bool verify})>[];

  @override
  Future<void> configure({
    required bool enabled,
    required WakeCondition condition,
    required bool verify,
    String detector = 'auto',
  }) async =>
      sent.add((enabled: enabled, condition: condition, verify: verify));
}

void main() {
  late ProviderContainer c;
  late _FakePlatform platform;

  setUp(() async {
    platform = _FakePlatform();
    final storage = openInMemoryStorage();
    c = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(storage),
        secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        wakePlatformProvider.overrideWithValue(platform),
      ],
    );
    addTearDown(c.dispose);
  });

  test('Standard: aus, nur beim Laden', () async {
    final s = await c.read(wakeServiceProvider.future);
    expect(s.enabled, isFalse);
    expect(s.condition, WakeCondition.charging);
  });

  test(
    'ohne eingelernte Stimme lässt sich der Dienst nicht einschalten',
    () async {
      final n = c.read(wakeServiceProvider.notifier);
      await c.read(wakeServiceProvider.future);
      expect(await n.setEnabled(enabled: true), isFalse);
      expect((await c.read(wakeServiceProvider.future)).enabled, isFalse);
      expect(platform.sent.where((s) => s.enabled), isEmpty);
    },
  );

  // WP140: reproduces `wake-start result=disabled` on the device: the model
  // alone can listen, yet the switch stayed off without an enrolled voice.
  group('Modell-Weg braucht keine Stimme', () {
    late FakeSpeechModelService models;

    Future<void> withModel({required bool installed}) async {
      models = FakeSpeechModelService();
      if (installed) {
        models.installed.add(SpeechModelCatalog.wakeClassifierWendelin.id);
      }
      final storage = openInMemoryStorage();
      c.dispose();
      c = ProviderContainer(
        overrides: [
          storageProvider.overrideWithValue(storage),
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
          wakePlatformProvider.overrideWithValue(platform),
          speechModelServiceProvider.overrideWith((_) async => models),
        ],
      );
      addTearDown(c.dispose);
      await c.read(modelStatesProvider.notifier).refresh();
      await c.read(wakeServiceProvider.future);
    }

    test('Modell da, keine Stimme: einschalten geht', () async {
      await withModel(installed: true);
      expect(c.read(wakeNeedsVoiceProvider), isFalse);
      expect(
        await c.read(wakeServiceProvider.notifier).setEnabled(enabled: true),
        isTrue,
      );
      expect(platform.sent.last.enabled, isTrue);
    });

    test('Modell fehlt, keine Stimme: gesperrt, nicht still aus', () async {
      await withModel(installed: false);
      expect(c.read(wakeNeedsVoiceProvider), isTrue);
      expect(
        await c.read(wakeServiceProvider.notifier).setEnabled(enabled: true),
        isFalse,
      );
    });

    test('Modell da, aber Wahl „Vorlagen“, keine Stimme: gesperrt', () async {
      await withModel(installed: true);
      await c
          .read(wakeDetectorProvider.notifier)
          .set(WakeDetectorChoice.templates);
      expect(c.read(wakeNeedsVoiceProvider), isTrue);
      expect(
        await c.read(wakeServiceProvider.notifier).setEnabled(enabled: true),
        isFalse,
      );
    });
  });

  test(
    'mit Stimme: einschalten, Bedingung ändern, Nachprüfung folgt',
    () async {
      await c.read(wakeSpeakersProvider.notifier).upsert('s1', 'Anna');
      await c.read(wakeServiceProvider.future);
      final n = c.read(wakeServiceProvider.notifier);
      expect(await n.setEnabled(enabled: true), isTrue);
      expect(platform.sent.last, (
        enabled: true,
        condition: WakeCondition.charging,
        verify: true,
      ));
      await n.setCondition(WakeCondition.always);
      expect(platform.sent.last.condition, WakeCondition.always);
      await c.read(wakeVerifyProvider.notifier).set(enabled: false);
      await Future<void>.delayed(Duration.zero);
      expect(platform.sent.last.verify, isFalse);
      // Aus.
      expect(await n.setEnabled(enabled: false), isTrue);
      expect(platform.sent.last.enabled, isFalse);
    },
  );

  test('gespeichert: ein neuer Container liest die Werte', () async {
    await c.read(wakeSpeakersProvider.notifier).upsert('s1', 'Anna');
    await c.read(wakeServiceProvider.future);
    final n = c.read(wakeServiceProvider.notifier);
    await n.setEnabled(enabled: true);
    await n.setCondition(WakeCondition.always);
    final c2 = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(c.read(storageProvider)),
        wakePlatformProvider.overrideWithValue(platform),
      ],
    );
    addTearDown(c2.dispose);
    final s = await c2.read(wakeServiceProvider.future);
    expect(s.enabled, isTrue);
    expect(s.condition, WakeCondition.always);
  });

  test(
    '„Aus“ aus der Benachrichtigung: der Schalter folgt, kein stilles Ein',
    () async {
      await c.read(wakeSpeakersProvider.notifier).upsert('s1', 'Anna');
      await c.read(wakeServiceProvider.future);
      final n = c.read(wakeServiceProvider.notifier);
      await n.setEnabled(enabled: true);
      platform.sent.clear();
      platform.current = const WakeServiceStatus(
        enabled: false,
        offByUser: true,
      );
      await n.sync();
      expect((await c.read(wakeServiceProvider.future)).enabled, isFalse);
      expect(
        await c.read(storageProvider).settings.get(wakeEnabledKey),
        isFalse,
      );
      expect(platform.sent, isEmpty);
      // Nächster push (z. B. Nachprüfung) schaltet nichts wieder ein.
      await c.read(wakeVerifyProvider.notifier).set(enabled: false);
      await Future<void>.delayed(Duration.zero);
      expect(platform.sent.where((s) => s.enabled), isEmpty);
    },
  );

  test('Rennen: eine vor dem Einschalten gelesene Antwort (aus, nicht durch '
      'den Nutzer) schaltet nicht wieder aus', () async {
    await c.read(wakeSpeakersProvider.notifier).upsert('s1', 'Anna');
    await c.read(wakeServiceProvider.future);
    final n = c.read(wakeServiceProvider.notifier);
    final gate = Completer<void>();
    platform.gate = gate.future;
    platform.current = const WakeServiceStatus(enabled: false);
    final pending = n.sync(); // liest „aus“ und wartet
    await n.setEnabled(enabled: true);
    gate.complete();
    await pending;
    expect((await c.read(wakeServiceProvider.future)).enabled, isTrue);
    expect(await c.read(storageProvider).settings.get(wakeEnabledKey), isTrue);
  });

  test('sync ohne Abweichung sendet die Einstellungen erneut', () async {
    await c.read(wakeSpeakersProvider.notifier).upsert('s1', 'Anna');
    await c.read(wakeServiceProvider.future);
    final n = c.read(wakeServiceProvider.notifier);
    await n.setEnabled(enabled: true);
    platform.sent.clear();
    platform.current = const WakeServiceStatus(enabled: true, running: true);
    await n.sync();
    expect(platform.sent.single.enabled, isTrue);
  });

  test('sync: Container während status() entsorgt, kein Ref-Fehler', () async {
    await c.read(wakeServiceProvider.future);
    final n = c.read(wakeServiceProvider.notifier);
    final gate = Completer<void>();
    platform.gate = gate.future;
    platform.current = const WakeServiceStatus(enabled: true, offByUser: true);
    final pending = n.sync();
    c.dispose();
    gate.complete();
    await pending; // UnmountedRefException (CI-Flake wake_lifecycle_test)
    expect(platform.sent, isEmpty);
  });

  test(
    'adoptStatus nach dispose: kein Ref-Fehler, nichts gespeichert',
    () async {
      await c.read(wakeSpeakersProvider.notifier).upsert('s1', 'Anna');
      await c.read(wakeServiceProvider.future);
      final n = c.read(wakeServiceProvider.notifier);
      await n.setEnabled(enabled: true);
      final storage = c.read(storageProvider);
      final pending = n.adoptStatus(
        const WakeServiceStatus(enabled: true, offByUser: true),
      );
      c.dispose();
      expect(await pending, isFalse); // UnmountedRefException without the check
      expect(await storage.settings.get(wakeEnabledKey), isTrue);
    },
  );

  test(
    'setEnabled: Container während des Wartens entsorgt, kein Ref-Fehler',
    () async {
      await c.read(wakeSpeakersProvider.notifier).upsert('s1', 'Anna');
      await c.read(wakeServiceProvider.future);
      final n = c.read(wakeServiceProvider.notifier);
      final pending = n.setEnabled(enabled: true);
      c.dispose();
      await pending;
      expect(platform.sent, isEmpty);
    },
  );

  test(
    'setCondition: Container während des Wartens entsorgt, kein Ref-Fehler',
    () async {
      await c.read(wakeServiceProvider.future);
      final n = c.read(wakeServiceProvider.notifier);
      final pending = n.setCondition(WakeCondition.always);
      c.dispose();
      await pending;
      expect(platform.sent, isEmpty);
    },
  );
}
