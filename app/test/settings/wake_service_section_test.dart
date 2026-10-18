// WP50 b: Schalter, Bedingung, Ton, Status und Erklärdialog des Aktivierungsworts.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/wake_service.dart';
import 'package:wendelin/di/wake_settings.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/platform/battery_platform.dart';
import 'package:wendelin/platform/wake/wake_platform.dart';
import 'package:wendelin/ui/design/design.dart' show WSwitch;
import 'package:wendelin/ui/settings/wake/wake_explain.dart';
import 'package:wendelin/ui/settings/wake/wake_service_section.dart'
    show wakeStopText;
import 'package:wendelin/ui/settings/wake/wake_word_screen.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';

import '../overlay/assistant_overlay_test.dart' show FakeAssistantPlatform;
import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'battery_hints_test.dart' show FakeBatteryPlatform;
import 'integrations_screen_test.dart' show settle;
import 'wake_word_screen_test.dart' show templates, wakeEnv;

final class FakeWakePlatform extends WakePlatform {
  WakeServiceStatus current = const WakeServiceStatus(holdsRole: true);
  final configured = <({bool enabled, WakeCondition condition})>[];

  @override
  Future<WakeServiceStatus> status() async => current;

  @override
  Future<void> configure({
    required bool enabled,
    required WakeCondition condition,
    required bool verify,
  }) async => configured.add((enabled: enabled, condition: condition));
}

class Setup {
  Setup({
    WakeServiceStatus status = const WakeServiceStatus(holdsRole: true),
    this.speaker = true,
    this.battery,
  }) : wake = FakeWakePlatform()..current = status,
       assistant = FakeAssistantPlatform();

  final FakeWakePlatform wake;
  final FakeAssistantPlatform assistant;
  final bool speaker;
  final BatteryStatus? battery;
  final fakeBattery = FakeBatteryPlatform();
  late final TestEnv env;
}

Future<(Setup, ProviderContainer)> pump(
  WidgetTester tester,
  Setup s, {
  bool enabled = false,
  WakeCondition condition = WakeCondition.charging,
  bool golden = false,
}) async {
  if (s.battery != null) s.fakeBattery.current = s.battery!;
  s.env = wakeEnv(
    extra: [
      wakePlatformProvider.overrideWithValue(s.wake),
      assistantPlatformProvider.overrideWithValue(s.assistant),
      batteryPlatformProvider.overrideWithValue(s.fakeBattery),
    ],
  );
  await tester.runAsync(() async {
    if (s.speaker) {
      await SecretWakeTemplateStore(s.env.secrets).save(templates('a'));
      await SecretWakeTemplateStore(s.env.secrets)
          .saveSpeakers(const [WakeSpeaker(id: 'a', name: 'Anna')]);
    }
    await s.env.storage.settings.set(wakeEnabledKey, enabled);
    await s.env.storage.settings.set(wakeConditionKey, condition.name);
  });
  setView(tester, Size(390, golden ? 1500 : 2400));
  await tester.pumpWidget(
    s.env.app(
      home: golden
          ? RepaintBoundary(key: goldenKey, child: const WakeWordScreen())
          : const WakeWordScreen(),
    ),
  );
  await settle(tester);
  final c = ProviderScope.containerOf(
    tester.element(find.byType(WakeWordScreen)),
  );
  return (s, c);
}

bool? switchValue(WidgetTester tester, String label) => tester
    .widget<WSwitch>(
      find.byWidgetPredicate((w) => w is WSwitch && w.semanticLabel == label),
    )
    .value;

bool switchLocked(WidgetTester tester) =>
    tester
        .widget<WSwitch>(
          find.byWidgetPredicate(
            (w) =>
                w is WSwitch &&
                w.semanticLabel == 'Aktivierungswort einschalten',
          ),
        )
        .onChanged ==
    null;

Finder status(String text) => find.descendant(
  of: find.byKey(const ValueKey('wakeStatus')),
  matching: find.textContaining(text),
);

void main() {
  testWidgets(
    'Rolle fehlt: Schalter gesperrt, Erklärung, Knopf zur Rollenwahl',
    (tester) async {
      final (s, _) = await pump(
        tester,
        Setup(status: const WakeServiceStatus()),
      );
      expect(switchLocked(tester), isTrue);
      expect(find.byKey(const ValueKey('wakeNeedRole')), findsOneWidget);
      await tester.tap(find.text('Assistenten wählen'));
      await settle(tester);
      expect(s.assistant.settingsOpened, 1);
    },
  );

  testWidgets('Nicht eingelernt: gesperrt, Hinweis mit Weg zum Einlernen', (
    tester,
  ) async {
    final (_, _) = await pump(tester, Setup(speaker: false));
    expect(switchLocked(tester), isTrue);
    expect(find.byKey(const ValueKey('wakeNeedVoice')), findsOneWidget);
    expect(find.byKey(const ValueKey('wakeNeedRole')), findsNothing);
    await tester.tap(find.text('Zum Einlernen'));
    await settle(tester);
    expect(find.text('Wer spricht?'), findsOneWidget);
  });

  testWidgets('Aus: Status „Aus“, Schalter frei, Standard nur beim Laden', (
    tester,
  ) async {
    await pump(tester, Setup());
    expect(status('Aus'), findsOneWidget);
    expect(switchLocked(tester), isFalse);
    expect(switchValue(tester, 'Aktivierungswort einschalten'), isFalse);
    expect(find.byKey(const ValueKey('wakeNeedRole')), findsNothing);
  });

  testWidgets('Läuft: Status „Läuft“, Ausschalten stoppt den Dienst', (
    tester,
  ) async {
    final (s, c) = await pump(
      tester,
      Setup(status: const WakeServiceStatus(running: true, holdsRole: true)),
      enabled: true,
    );
    expect(status('Läuft'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is WSwitch && w.semanticLabel == 'Aktivierungswort einschalten',
      ),
    );
    await settle(tester);
    expect((await c.read(wakeServiceProvider.future)).enabled, isFalse);
    expect(s.wake.configured.last.enabled, isFalse);
  });

  testWidgets('Pausiert: bis Uhrzeit, und wartet auf das Laden', (
    tester,
  ) async {
    await pump(
      tester,
      Setup(
        status: WakeServiceStatus(
          running: true,
          holdsRole: true,
          pausedUntil: DateTime(2026, 10, 14, 9, 5),
        ),
      ),
      enabled: true,
    );
    expect(status('Pausiert bis 09:05'), findsOneWidget);
    await pump(tester, Setup(), enabled: true);
    expect(status('Pausiert: wartet auf das Laden'), findsOneWidget);
  });

  testWidgets('Vom System beendet: mit letztem Grund', (tester) async {
    await pump(
      tester,
      Setup(
        status: const WakeServiceStatus(holdsRole: true, lastStop: 'timeout'),
      ),
      enabled: true,
      condition: WakeCondition.always,
    );
    expect(
      status('Vom System beendet (Zeitlimit von Android)'),
      findsOneWidget,
    );
    expect(find.textContaining('timeout'), findsNothing);
  });

  test('Stopp-Gründe: verständlicher Text, nie rohe Codes', () {
    const table = {
      'timeout': 'Vom System beendet (Zeitlimit von Android)',
      'no-role': 'Beendet: Wendelin ist nicht mehr dein Assistent',
      'no-permission': 'Beendet: Mikrofon-Berechtigung fehlt',
      'engine-failed': 'Beendet: Die Erkennung ist ausgefallen',
      'not-charging': 'Beendet: Das Gerät lädt nicht mehr',
      'unplug': 'Beendet: Das Gerät lädt nicht mehr',
      'user-off': 'Aus',
      'seltsam': 'Vom System beendet',
      null: 'Vom System beendet',
    };
    table.forEach((reason, text) {
      expect(
        wakeStopText(AppLocalizationsDe(), reason),
        text,
        reason: '$reason',
      );
    });
    for (final r in ['no-role', 'engine-failed']) {
      expect(wakeStopText(AppLocalizationsDe(), r), isNot(contains('System')));
    }
  });

  test('Erklärtexte: ehrlich zu Benachrichtigung und Anbieter', () {
    final all = wakeExplainPoints(AppLocalizationsDe())
        .map((p) => '${p.$1} ${p.$2}')
        .join(' ');
    expect(all, isNot(contains('nicht ausblenden')));
    expect(all, contains('wegwischen'));
    expect(all, contains('als Text an den gewählten KI-Anbieter'));
    expect(all, isNot(contains('Alles bleibt auf dem Gerät')));
  });

  testWidgets('Bedingung „Immer“ und Bestätigungston lassen sich ändern', (
    tester,
  ) async {
    final (s, c) = await pump(tester, Setup());
    await tester.tap(find.byKey(const ValueKey('wakeCondition.always')));
    await settle(tester);
    expect(
      (await c.read(wakeServiceProvider.future)).condition,
      WakeCondition.always,
    );
    expect(await c.read(wakeToneProvider.future), isTrue);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is WSwitch && w.semanticLabel == 'Bestätigungston',
      ),
    );
    await settle(tester);
    expect(await s.env.storage.settings.get(wakeToneKey), isFalse);
  });

  testWidgets('Einschalten: Erklärdialog, Berechtigungen, Akku-Ausnahme', (
    tester,
  ) async {
    final (s, c) = await pump(
      tester,
      Setup(battery: const BatteryStatus(ignoringOptimizations: false)),
    );
    s.env.microphone.granted = false;
    s.env.notifier.granted = false;
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is WSwitch && w.semanticLabel == 'Aktivierungswort einschalten',
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('wakeExplain')), findsOneWidget);
    for (final t in ['Dauerhafte Benachrichtigung', 'Mikrofon-Punkt', 'Akku']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.textContaining('bleibt auf dem Gerät'), findsOneWidget);
    await tester.tap(find.text('Einschalten'));
    await settle(tester);
    // Mikrofon: eigener Dialog, Android verweigert -> bleibt aus.
    expect(find.text('Mikrofon erlauben?'), findsOneWidget);
    await tester.tap(find.text('Erlauben'));
    await settle(tester);
    expect((await c.read(wakeServiceProvider.future)).enabled, isFalse);

    s.env.microphone.granted = true;
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is WSwitch && w.semanticLabel == 'Aktivierungswort einschalten',
      ),
    );
    await settle(tester);
    // Erklärung nur einmal bestätigt? Nein: erst nach dem Einschalten.
    await tester.tap(find.text('Einschalten'));
    await settle(tester);
    expect(s.env.notifier.permissionRequests, 1);
    expect((await c.read(wakeServiceProvider.future)).enabled, isTrue);
    expect(s.wake.configured.last.enabled, isTrue);
    expect(find.text('Akku-Optimierung ausnehmen?'), findsOneWidget);
    await tester.tap(find.text('Ausnehmen'));
    await settle(tester);
    expect(s.fakeBattery.requested, 1);

    // Ausschalten und wieder einschalten: keine Erklärung mehr.
    await c.read(wakeServiceProvider.notifier).setEnabled(enabled: false);
    await settle(tester);
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is WSwitch && w.semanticLabel == 'Aktivierungswort einschalten',
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('wakeExplain')), findsNothing);
  });

  testWidgets('Xiaomi: Hersteller-Hinweis im Erklärdialog und auf der Seite', (
    tester,
  ) async {
    await pump(
      tester,
      Setup(
        battery: const BatteryStatus(vendor: 'xiaomi', vendorSettings: true),
      ),
    );
    expect(find.byKey(const ValueKey('vendorChecklist')), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is WSwitch && w.semanticLabel == 'Aktivierungswort einschalten',
      ),
    );
    await settle(tester);
    expect(find.textContaining('Xiaomi / HyperOS'), findsWidgets);
    expect(wakeExplainPoints(AppLocalizationsDe()).length, 4);
  });

  testWidgets('Erklärdialog abbrechen lässt den Dienst aus', (tester) async {
    final (_, c) = await pump(tester, Setup());
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is WSwitch && w.semanticLabel == 'Aktivierungswort einschalten',
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect((await c.read(wakeServiceProvider.future)).enabled, isFalse);
  });

  testWidgets(
    'Seite offen: „Aus“ aus der Benachrichtigung schaltet den Schalter',
    (tester) async {
      final (s, c) = await pump(
        tester,
        Setup(
          status: const WakeServiceStatus(
            running: true,
            enabled: true,
            holdsRole: true,
          ),
        ),
        enabled: true,
      );
      expect(switchValue(tester, 'Aktivierungswort einschalten'), isTrue);
      s.wake.current = const WakeServiceStatus(
        enabled: false,
        offByUser: true,
        holdsRole: true,
      );
      c.invalidate(wakeStatusProvider);
      await settle(tester);
      expect(switchValue(tester, 'Aktivierungswort einschalten'), isFalse);
      expect(await s.env.storage.settings.get(wakeEnabledKey), isFalse);
    },
  );

  testWidgets(
    'App-Start liest wakeServiceProvider: Nachprüfung wird gesendet',
    (tester) async {
      final wake = FakeWakePlatform();
      final env = wakeEnv(
        extra: [wakePlatformProvider.overrideWithValue(wake)],
      );
      setView(tester, const Size(390, 1400));
      await tester.pumpWidget(env.app());
      await settle(tester);
      expect(wake.configured, isNotEmpty);
    },
  );
}
