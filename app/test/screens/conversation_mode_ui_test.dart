// WP51: Folgefenster in der Zuhör-Leiste und im Overlay, einmalige Nachfrage
// im Hauptbildschirm, Einstellung „Gespräch“.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/overlay/overlay_sheet.dart';
import 'package:wendelin/ui/screens/conversation_offer_card.dart';
import 'package:wendelin/ui/screens/main_parts.dart';
import 'package:wendelin/ui/settings/voice_conversation_section.dart';
import 'package:wendelin/ui/settings/voice_screen.dart';
import 'package:wendelin/voice/conversation_offer.dart';
import 'package:wendelin_core/wendelin_core.dart' show PrivacyLevel;
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../settings/integrations_screen_test.dart' show settle;
import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'main_screen_test.dart' show containerOf, pumpApp;

final _t0 = DateTime(2026, 10, 14, 12);

Widget _composer(DateTime? until, DateTime Function() now) => Composer(
  running: false,
  mic: MicState.listening,
  levels: const [0.3, 0.2, 0.7],
  followUpUntil: until,
  now: now,
  onMic: () {},
  onSend: (_) => true,
);

void main() {
  group('Zuhör-Leiste im Folgefenster', () {
    testWidgets('„Ich höre noch zu …“ mit Restzeit, die abläuft', (
      tester,
    ) async {
      setView(tester, const Size(390, 300));
      var now = _t0;
      await tester.pumpWidget(
        themed(
          RepaintBoundary(
            key: goldenKey,
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: _composer(
                  _t0.add(const Duration(seconds: 5)),
                  () => now,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Ich höre noch zu … 5 s'), findsOneWidget);
      expect(find.text('Ich höre zu …'), findsNothing);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/composer_follow_up.png'),
      );

      now = _t0.add(const Duration(milliseconds: 3200));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ich höre noch zu … 2 s'), findsOneWidget);
      now = _t0.add(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ich höre noch zu … 0 s'), findsOneWidget);
    });

    testWidgets('ohne Fenster: unverändert „Ich höre zu …“', (tester) async {
      setView(tester, const Size(390, 300));
      await tester.pumpWidget(
        themed(Scaffold(body: _composer(null, () => _t0))),
      );
      expect(find.text('Ich höre zu …'), findsOneWidget);
      expect(find.textContaining('noch zu'), findsNothing);
    });

    test('Restzeit rundet auf und wird nie negativ', () {
      final until = _t0.add(const Duration(seconds: 5));
      expect(followUpSeconds(until, _t0), 5);
      expect(
        followUpSeconds(until, _t0.add(const Duration(milliseconds: 1))),
        5,
      );
      expect(
        followUpSeconds(until, _t0.add(const Duration(milliseconds: 4001))),
        1,
      );
      expect(followUpSeconds(until, _t0.add(const Duration(seconds: 9))), 0);
    });
  });

  group('Overlay', () {
    OverlaySheet sheet({
      bool mode = false,
      DateTime? until,
      DateTime Function()? now,
    }) => OverlaySheet(
      providerName: 'Claude',
      privacy: PrivacyLevel.standard,
      exchange: const OverlayExchange(),
      mic: until == null ? MicState.idle : MicState.listening,
      levels: const [],
      onMic: () {},
      onClose: () {},
      onKeyboard: () {},
      onUndo: (_) {},
      listening: until != null,
      conversationMode: mode,
      followUpUntil: until,
      now: now ?? () => _t0,
    );

    testWidgets('Hinweis je Zustand des Gesprächsmodus', (tester) async {
      setView(tester, screenSize);
      await tester.pumpWidget(themed(Scaffold(body: sheet())));
      expect(find.text(OverlaySheet.followUpComingHint), findsOneWidget);

      await tester.pumpWidget(themed(Scaffold(body: sheet(mode: true))));
      expect(find.text(OverlaySheet.followUpHint), findsOneWidget);

      await tester.pumpWidget(
        themed(
          Scaffold(
            body: sheet(mode: true, until: _t0.add(const Duration(seconds: 4))),
          ),
        ),
      );
      expect(find.text(OverlaySheet.followUpWindowHint(4)), findsOneWidget);
      expect(find.text('Ich höre noch zu …'), findsOneWidget);
    });
  });

  group('Einmalige Nachfrage im Hauptbildschirm', () {
    testWidgets('Karte mit Ja/Nein und Hinweis, „Ja“ speichert, Karte weg', (
      tester,
    ) async {
      final env = TestEnv(demo: true);
      await pumpApp(tester, env);
      final c = containerOf(tester);
      expect(find.byType(ConversationOfferCard), findsNothing);

      await c.read(conversationOfferProvider.notifier).offer();
      await tester.pump();
      expect(find.text(conversationOfferQuestion), findsOneWidget);
      expect(find.text(conversationOfferHint), findsOneWidget);
      expect(find.textContaining('Einstellungen'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, 'Ja'));
      await settle(tester);
      expect(find.byType(ConversationOfferCard), findsNothing);
      final s = await c.read(voiceSettingsProvider.future);
      expect(s.conversationMode, isTrue);
      expect(s.conversationAsked, isTrue);
      expect(
        (await env.storage.settings.get(voiceSettingsKey))?.conversationAsked,
        isTrue,
        reason: 'die Antwort ist gespeichert',
      );

      await c.read(conversationOfferProvider.notifier).offer();
      await tester.pump();
      expect(
        find.byType(ConversationOfferCard),
        findsNothing,
        reason: 'die Frage kommt nie wieder',
      );
    });

    testWidgets('„Nein“ lässt den Gesprächsmodus aus', (tester) async {
      await pumpApp(tester, TestEnv(demo: true));
      final c = containerOf(tester);
      await c.read(conversationOfferProvider.notifier).offer();
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Nein'));
      await settle(tester);
      final s = await c.read(voiceSettingsProvider.future);
      expect(s.conversationMode, isFalse);
      expect(s.conversationAsked, isTrue);
    });
  });

  group('Einstellungen → Sprache → Gespräch', () {
    Future<ProviderContainer> open(
      WidgetTester tester, {
      bool detector = false,
    }) async {
      final env = TestEnv(
        extraOverrides: [
          if (detector)
            bargeInDetectorProvider.overrideWithValue(FakeBargeInDetector()),
        ],
      );
      setView(tester, const Size(390, 5000));
      await tester.pumpWidget(env.app(home: const VoiceScreen()));
      await settle(tester);
      return ProviderScope.containerOf(
        tester.element(find.byType(VoiceScreen)),
      );
    }

    testWidgets('Standard aus; Schalter speichert und beendet die Nachfrage', (
      tester,
    ) async {
      final c = await open(tester);
      await tester.scrollUntilVisible(
        find.text('Weiter zuhören nach der Antwort'),
        300,
      );
      final toggle = find.descendant(
        of: find.widgetWithText(InkWell, 'Weiter zuhören nach der Antwort'),
        matching: find.byType(WSwitch),
      );
      expect(tester.widget<WSwitch>(toggle).value, isFalse);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await settle(tester);
      final s = await c.read(voiceSettingsProvider.future);
      expect(s.conversationMode, isTrue);
      expect(s.conversationAsked, isTrue);
    });

    testWidgets('Barge-in: ohne Detektor „nicht verfügbar“ und gesperrt', (
      tester,
    ) async {
      await open(tester);
      await tester.scrollUntilVisible(find.text(bargeInUnavailableText), 300);
      for (final label in bargeInLabels.values) {
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
              .onSelected,
          isNull,
        );
      }
    });

    testWidgets('Barge-in: mit Detektor wählbar, Standard Schlüsselwörter', (
      tester,
    ) async {
      final c = await open(tester, detector: true);
      await tester.scrollUntilVisible(
        find.text(bargeInLabels[BargeInMode.speech]!),
        300,
      );
      expect(find.text(bargeInUnavailableText), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Schlüsselwörter'),
            )
            .selected,
        isTrue,
      );
      final off = find.widgetWithText(
        ChoiceChip,
        bargeInLabels[BargeInMode.off]!,
      );
      await tester.ensureVisible(off);
      await tester.tap(off);
      await settle(tester);
      expect(
        (await c.read(voiceSettingsProvider.future)).bargeIn,
        BargeInMode.off,
      );
    });
  });
}
