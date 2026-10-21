import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/assistant_screen.dart';
import 'package:wendelin/ui/settings/settings_page.dart';

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
    expect(find.text(AppLocalizationsDe().assistantSwitchHint), findsOneWidget);
    expect(
      AppLocalizationsDe().assistantSwitchHint,
      contains('Digitaler Assistent'),
    );
    await tester.tap(find.byType(WSwitch));
    await tester.pump();
    expect(platform.recognizerOffered, isFalse);
    expect(tester.widget<WSwitch>(find.byType(WSwitch)).value, isFalse);
  });

  group('Standard-Assistent (WP32)', () {
    testWidgets('ohne Rolle: Knopf, kein Hilfstext, kein Link', (tester) async {
      await pumpAssistant(tester, FakeAssistantPlatform());
      expect(find.text('Als Standard-Assistent setzen'), findsOneWidget);
      expect(find.textContaining('Android öffnet die Auswahl'), findsNothing);
      expect(find.text('In Android ändern'), findsNothing);
    });

    testWidgets('mit Rolle: Haken, kein Knopf, Link „In Android ändern“', (
      tester,
    ) async {
      final platform = FakeAssistantPlatform()..isDefault = true;
      await pumpAssistant(tester, platform);
      expect(find.text('Wendelin ist Standard-Assistent'), findsOneWidget);
      expect(find.text('Als Standard-Assistent setzen'), findsNothing);
      expect(
        find.descendant(
          of: find.widgetWithText(
            SettingsRow,
            'Wendelin ist Standard-Assistent',
          ),
          matching: find.byType(CheckStatusIcon),
        ),
        findsOneWidget,
      );
      final link = find.widgetWithText(OutlinedButton, 'In Android ändern');
      expect(tester.getSize(link).height, greaterThanOrEqualTo(WSize.touchMin));
      await tester.tap(link);
      await tester.pump();
      expect(platform.settingsOpened, 1);
    });
  });

  testWidgets('Persönlichkeit: zwei Zeilen, wächst bis fünf', (tester) async {
    await pumpAssistant(tester, FakeAssistantPlatform());
    final persona = find.descendant(
      of: find.byKey(const ValueKey('persona')),
      matching: find.byType(TextField),
      matchRoot: true,
    );
    final field = tester.widget<TextField>(persona);
    expect(field.minLines, 2);
    expect(field.maxLines, 5);
    final empty = tester.getSize(persona).height;
    await tester.enterText(persona, 'eins\nzwei\ndrei\nvier');
    await tester.pump();
    expect(tester.getSize(persona).height, greaterThan(empty));
  });

  group('B12: System-Spracherkennung', () {
    WSwitch recognizerSwitch(WidgetTester tester) => tester.widget<WSwitch>(
      find.descendant(
        of: find.byKey(const ValueKey('recognizerRow')),
        matching: find.byType(WSwitch),
      ),
    );

    testWidgets('anderer Dienst: Schalter ausgegraut, Wert bleibt, Hinweis', (
      tester,
    ) async {
      final platform = FakeAssistantPlatform()
        ..isDefault = true
        ..recognition = const RecognitionServiceStatus(
          RecognitionServiceState.other,
          appName: 'Google',
        );
      await pumpAssistant(tester, platform);
      expect(
        find.textContaining(AppLocalizationsDe().assistantNotAvailable),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Android nutzt für andere Apps Google. Das lässt sich auf diesem '
          'Gerät nicht umstellen.',
        ),
        findsOneWidget,
      );
      final s = recognizerSwitch(tester);
      expect(s.onChanged, isNull);
      expect(s.value, isTrue, reason: 'gespeicherte Einstellung bleibt');
      expect(
        s.semanticLabel,
        contains(AppLocalizationsDe().assistantNotAvailable),
      );
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(
                of: find.byWidget(s),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        WOpacity.inactive,
      );
      await tester.tap(find.byType(WSwitch));
      await tester.pump();
      expect(platform.recognizerOffered, isTrue);
      expect(find.text(AppLocalizationsDe().assistantSwitchHint), findsNothing);
    });

    testWidgets('ohne App-Namen: „einen anderen Dienst“', (tester) async {
      final platform = FakeAssistantPlatform()
        ..isDefault = true
        ..recognition = const RecognitionServiceStatus(
          RecognitionServiceState.other,
        );
      await pumpAssistant(tester, platform);
      expect(
        find.textContaining(
          'Android nutzt für andere Apps einen anderen Dienst.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('anderer Dienst ohne Rolle: bedienbar, Wert kann sich ändern', (
      tester,
    ) async {
      final platform = FakeAssistantPlatform()
        ..recognition = const RecognitionServiceStatus(
          RecognitionServiceState.other,
          appName: 'Google',
        );
      await pumpAssistant(tester, platform);
      expect(
        find.textContaining(AppLocalizationsDe().assistantNotAvailable),
        findsNothing,
      );
      expect(
        find.textContaining(
          'Android nutzt für andere Apps derzeit Google. Das kann sich '
          'ändern, sobald Wendelin Standard-Assistent ist.',
        ),
        findsOneWidget,
      );
      expect(recognizerSwitch(tester).onChanged, isNotNull);
    });

    testWidgets('anderer Dienst, gespeichert „aus“: wieder einschaltbar', (
      tester,
    ) async {
      final platform = FakeAssistantPlatform()
        ..isDefault = true
        ..recognizerOffered = false
        ..recognition = const RecognitionServiceStatus(
          RecognitionServiceState.other,
          appName: 'Google',
        );
      await pumpAssistant(tester, platform);
      expect(recognizerSwitch(tester).value, isFalse);
      expect(recognizerSwitch(tester).onChanged, isNotNull);
      expect(find.textContaining('hängt vom Gerät ab'), findsOneWidget);
      final checks = platform.recognitionChecks;
      await tester.tap(find.byType(WSwitch));
      await tester.pump();
      await tester.pump();
      expect(platform.recognizerOffered, isTrue);
      expect(platform.recognitionChecks, greaterThan(checks), reason: 'neu');
      // Android stays with Google: now locked and marked.
      expect(recognizerSwitch(tester).onChanged, isNull);
      expect(
        find.textContaining(AppLocalizationsDe().assistantNotAvailable),
        findsOneWidget,
      );
    });

    for (final isDefault in [true, false]) {
      testWidgets('verweist auf Wendelin, aber aus (Rolle: $isDefault)', (
        tester,
      ) async {
        final platform = FakeAssistantPlatform()
          ..isDefault = isDefault
          ..recognizerOffered = !isDefault
          ..recognition = const RecognitionServiceStatus(
            RecognitionServiceState.inactive,
          );
        await pumpAssistant(tester, platform);
        expect(
          find.textContaining(
            (isDefault
                ? AppLocalizationsDe().assistantInactiveDefault
                : AppLocalizationsDe().assistantInactiveNotDefault),
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            AppLocalizationsDe().assistantRecognizerActiveHint,
          ),
          findsNothing,
        );
        expect(recognizerSwitch(tester).onChanged, isNotNull);
      });
    }

    for (final state in [
      RecognitionServiceState.active,
      RecognitionServiceState.unknown,
    ]) {
      testWidgets('${state.name}: Schalter bedienbar', (tester) async {
        final platform = FakeAssistantPlatform()
          ..recognition = RecognitionServiceStatus(state);
        await pumpAssistant(tester, platform);
        expect(
          find.textContaining(AppLocalizationsDe().assistantNotAvailable),
          findsNothing,
        );
        expect(recognizerSwitch(tester).onChanged, isNotNull);
        expect(
          find.textContaining(
            AppLocalizationsDe().assistantRecognizerActiveHint,
          ),
          state == RecognitionServiceState.active
              ? findsOneWidget
              : findsNothing,
        );
      });
    }

    testWidgets('Neuprüfung bei Rückkehr in die App', (tester) async {
      final platform = FakeAssistantPlatform()
        ..isDefault = true
        ..recognition = const RecognitionServiceStatus(
          RecognitionServiceState.active,
        );
      await pumpAssistant(tester, platform);
      final before = platform.recognitionChecks;
      platform.recognition = const RecognitionServiceStatus(
        RecognitionServiceState.other,
        appName: 'Google',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(platform.recognitionChecks, greaterThan(before));
      expect(recognizerSwitch(tester).onChanged, isNull);
    });
  });
}
