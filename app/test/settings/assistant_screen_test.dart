import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/assistant_screen.dart';

import '../overlay/assistant_overlay_test.dart' show FakeAssistantPlatform;
import '../support/test_env.dart';
import '../ui/helpers.dart';

Future<void> pumpAssistant(
  WidgetTester tester,
  FakeAssistantPlatform platform,
) async {
  setView(tester, const Size(390, 1200));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...TestEnv().overrides,
        assistantPlatformProvider.overrideWithValue(platform),
      ],
      retry: (_, _) => null,
      child: themed(const AssistantScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('nicht gesetzt: Button öffnet die Systemauswahl', (tester) async {
    final platform = FakeAssistantPlatform();
    await pumpAssistant(tester, platform);
    expect(find.text('Nicht als Standard-Assistent gesetzt'), findsOneWidget);
    await tester.tap(find.text('Als Standard-Assistent setzen'));
    await tester.pump();
    expect(platform.settingsOpened, 1);
  });

  testWidgets('gesetzt: Status mit Haken, nach Rückkehr neu geprüft', (
    tester,
  ) async {
    final platform = FakeAssistantPlatform();
    await pumpAssistant(tester, platform);
    platform.isDefault = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.text('Wendelin ist Standard-Assistent'), findsOneWidget);
    expect(find.byType(CheckStatusIcon), findsOneWidget);
  });

  testWidgets('Spracherkennung für andere Apps: an, ausschalten', (
    tester,
  ) async {
    final platform = FakeAssistantPlatform();
    await pumpAssistant(tester, platform);
    expect(
      find.text('Als Spracherkennung für andere Apps anbieten'),
      findsOneWidget,
    );
    expect(tester.widget<WSwitch>(find.byType(WSwitch)).value, isTrue);
    // Hinweis: nach einem Assistentenwechsel die Spracheingabe neu wählen.
    expect(find.text(assistantSwitchHint), findsOneWidget);
    expect(assistantSwitchHint, contains('Digitaler Assistent'));
    await tester.tap(find.byType(WSwitch));
    await tester.pump();
    expect(platform.recognizerOffered, isFalse);
    expect(tester.widget<WSwitch>(find.byType(WSwitch)).value, isFalse);
  });
}
