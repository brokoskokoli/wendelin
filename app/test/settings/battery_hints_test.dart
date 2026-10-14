import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/platform/battery_platform.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/assistant_screen.dart';
import 'package:wendelin/ui/settings/battery_hints.dart';
import 'package:wendelin/ui/settings/settings_page.dart';

import '../overlay/assistant_overlay_test.dart' show FakeAssistantPlatform;
import '../support/test_env.dart';
import '../ui/helpers.dart';

class FakeBatteryPlatform extends BatteryPlatform {
  BatteryStatus current = const BatteryStatus();
  int requested = 0;
  int batterySettings = 0;
  int vendorSettingsOpened = 0;

  @override
  Future<BatteryStatus> status() async => current;

  @override
  Future<bool> requestIgnoreOptimizations() async {
    requested++;
    return true;
  }

  @override
  Future<bool> openBatterySettings() async {
    batterySettings++;
    return true;
  }

  @override
  Future<bool> openVendorSettings() async {
    vendorSettingsOpened++;
    return true;
  }
}

Future<void> pumpHints(WidgetTester tester, FakeBatteryPlatform battery) async {
  setView(tester, const Size(390, 1200));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...TestEnv().overrides,
        assistantPlatformProvider.overrideWithValue(FakeAssistantPlatform()),
        batteryPlatformProvider.overrideWithValue(battery),
      ],
      retry: (_, _) => null,
      child: themed(const AssistantScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('Optimierung inaktiv, normaler Bucket, kein Hersteller: nichts', (
    tester,
  ) async {
    await pumpHints(
      tester,
      FakeBatteryPlatform()
        ..current = const BatteryStatus(bucket: StandbyBucket.active),
    );
    expect(find.text('Zuverlässig öffnen'), findsNothing);
    expect(find.text(batteryOptimizedTitle), findsNothing);
  });

  testWidgets('Optimierung aktiv: Hinweis und Knopf fragt die Ausnahme an', (
    tester,
  ) async {
    final battery = FakeBatteryPlatform()
      ..current = const BatteryStatus(ignoringOptimizations: false);
    await pumpHints(tester, battery);
    expect(find.text(batteryOptimizedTitle), findsOneWidget);
    await tester.tap(find.text('Keine Einschränkung erlauben'));
    await tester.pump();
    expect(battery.requested, 1);
    // Zurück aus dem Systemdialog: Status neu geprüft, Hinweis verschwindet.
    battery.current = const BatteryStatus();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.text(batteryOptimizedTitle), findsNothing);
  });

  testWidgets('Bucket rare und restricted werden angezeigt', (tester) async {
    final battery = FakeBatteryPlatform()
      ..current = const BatteryStatus(bucket: StandbyBucket.rare);
    await pumpHints(tester, battery);
    expect(find.text('App-Standby: selten genutzt'), findsOneWidget);
    battery.current = const BatteryStatus(bucket: StandbyBucket.restricted);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.text('App-Standby: eingeschränkt'), findsOneWidget);
  });

  testWidgets('Hersteller erkannt mit Deep-Link: Checkliste und Knopf', (
    tester,
  ) async {
    final battery = FakeBatteryPlatform()
      ..current = const BatteryStatus(vendor: 'xiaomi', vendorSettings: true);
    await pumpHints(tester, battery);
    expect(find.text('Xiaomi / HyperOS / MIUI'), findsOneWidget);
    expect(find.textContaining('Keine Einschränkungen'), findsOneWidget);
    await tester.tap(find.text('Einstellungen des Herstellers öffnen'));
    await tester.pump();
    expect(battery.vendorSettingsOpened, 1);
  });

  testWidgets(
    'Hersteller ohne erreichbare Seite: nur Text, Akku-Einstellungen',
    (tester) async {
      final battery = FakeBatteryPlatform()
        ..current = const BatteryStatus(vendor: 'samsung');
      await pumpHints(tester, battery);
      expect(find.text('Samsung'), findsOneWidget);
      expect(find.text('Einstellungen des Herstellers öffnen'), findsNothing);
      await tester.tap(find.text('Akku-Einstellungen öffnen'));
      await tester.pump();
      expect(battery.batterySettings, 1);
    },
  );

  testWidgets('Unbekannter Hersteller: keine Checkliste', (tester) async {
    await pumpHints(
      tester,
      FakeBatteryPlatform()..current = const BatteryStatus(vendor: 'fairphone'),
    );
    expect(find.byKey(const ValueKey('vendorChecklist')), findsNothing);
  });

  // Drei kleine Goldens (je eine Karte) statt des ganzen Screens: jedes bleibt
  // weit unter den CI-Toleranzen (Glyphen-Antialiasing, `golden_tolerance.dart`).
  // Das Zusammenspiel im Screen prüfen die Widget-Tests oben.
  final cards = <(String, SettingsRow)>[
    (
      'akku_optimierung',
      const SettingsRow(
        title: batteryOptimizedTitle,
        detail: batteryOptimizedDetail,
      ),
    ),
    (
      'akku_standby',
      SettingsRow(
        title: standbyBucketTitle(StandbyBucket.rare),
        detail: standbyBucketDetail,
      ),
    ),
    (
      'akku_hersteller',
      SettingsRow(
        title: vendorChecklists['xiaomi']!.$1,
        detail: vendorChecklists['xiaomi']!.$2,
      ),
    ),
  ];
  for (final (name, row) in cards) {
    testWidgets('Golden Assistent: $name', tags: ['golden'], (tester) async {
      await pumpComponent(tester, [
        SectionCard(children: [row]),
      ]);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/assistent_$name.png'),
      );
    });
  }
}
