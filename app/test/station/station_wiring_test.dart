import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/integrations/clipboard_spec.dart';
import 'package:wendelin/di/integrations/station_spec.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/platform/channels.dart';
import 'package:wendelin/station/ui/station_app.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support/test_env.dart';
import 'station_support.dart';

void main() {
  group('Sprachbefehl', () {
    test(
      'startet nur entsperrt: Sperrflag aus, Tool lehnt gesperrt ab',
      () async {
        final env = TestEnv(enabled: const {'station'});
        final c = env.container();
        addTearDown(c.dispose);
        final registry = c.read(toolRegistryProvider);
        await registry.refresh();
        expect(registry.status('station'), IntegrationStatus.active);
        // Im gesperrten Zustand laufen nur Integrationen mit dem Flag (WP53).
        expect(stationSpec.allowedWhileLocked, isFalse);
        expect(clipboardSpec.allowedWhileLocked, isFalse);

        final catalog = registry.catalogFor(PrivacyLevel.local, sessionId: 's');
        final ctx = ToolContext(
          sessionId: 's',
          clock: FixedClock(testNow),
          locale: 'de-DE',
          timeZone: 'Europe/Berlin',
        );
        final tool = catalog.lookup('station__start')!;
        env.station.locked = true;
        final refused = await tool.execute({}, ctx);
        expect(refused.isError, isTrue);
        expect(env.station.starts, 0);

        env.station.locked = false;
        final ok = await tool.execute({}, ctx);
        expect(ok.isError, isFalse, reason: ok.text);
        expect(env.station.starts, 1);
      },
    );

    test('kein Werkzeug beendet die Station', () async {
      final env = TestEnv(enabled: const {'station'});
      final c = env.container();
      addTearDown(c.dispose);
      final registry = c.read(toolRegistryProvider);
      await registry.refresh();
      final catalog = registry.catalogFor(PrivacyLevel.local, sessionId: 's');
      final names = [
        for (final t in catalog.activeSpecs())
          if (t.name.startsWith('station__')) t.name,
      ];
      expect(names, ['station__start']);
      expect(catalog.lookup('station__end'), isNull);
      expect(catalog.lookup('station__stop'), isNull);
    });
  });

  group('Chat-Sichtbarkeit', () {
    const wake = MethodChannel(wakeChannelName);
    final calls = <String>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(wake, (call) async {
            calls.add(call.method);
            return null;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(wake, null),
    );

    testWidgets('die Station meldet sich nie als sichtbarer Chat', (
      tester,
    ) async {
      final host = FakeStationHost();
      await tester.pumpWidget(
        ProviderScope(
          overrides: stationOverrides(
            clock: MutableClock(DateTime(2026, 10, 20, 12)),
            host: host,
            data: FakeStationData(),
          ),
          child: const StationApp(),
        ),
      );
      await tester.pump();
      // Berührung, Hintergrund und wieder davor: nichts davon wird gemeldet.
      await tester.tapAt(const Offset(50, 50));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byKey(const ValueKey('stationClock')), findsOneWidget);
      expect(calls, isEmpty, reason: 'Aufrufe am Wake-Kanal: $calls');
      await tester.pump(const Duration(seconds: 31));
    });

    test('der Code der Station kennt weder WakeChat noch den Wake-Kanal', () {
      final files = Directory('lib/station')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      expect(files, isNotEmpty);
      for (final f in files) {
        final text = f.readAsStringSync();
        for (final banned in [
          'setChatVisible',
          'WakeChat',
          'wakeChannelName',
        ]) {
          expect(text, isNot(contains(banned)), reason: '${f.path}: $banned');
        }
      }
    });
  });
}
