import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_reducer.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/routing.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/overlay/overlay_sheet.dart';
import 'package:wendelin/ui/screens/confirmation_sheet.dart';
import 'package:wendelin/ui/screens/main_parts.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/ui/screens/private_banner.dart';
import 'package:wendelin/ui/settings/memory_screen.dart';
import 'package:wendelin/ui/settings/routing/routing_screen.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../settings/integrations_screen_test.dart' show settle;
import '../settings/other_screens_test.dart' show pumpPage;
import '../support/test_env.dart';
import '../ui/helpers.dart';

Future<ProviderContainer> _pumpMain(WidgetTester tester, TestEnv env) async {
  setView(tester, screenSize);
  await tester.pumpWidget(
    env.app(home: const MainScreen(restoreSession: false)),
  );
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(MainScreen)));
}

void main() {
  group('Unterhaltung privat', () {
    testWidgets('Hauptbildschirm zeigt seit wann, „Neues Gespräch“ endet', (
      tester,
    ) async {
      final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
      final c = await _pumpMain(tester, env);
      expect(find.byType(PrivateConversationBanner), findsNothing);

      c
          .read(agentControllerProvider.notifier)
          .seed(ConversationState(privateSince: testNow));
      await tester.pumpAndSettle();
      expect(
        find.text('Vertraulich: Gedächtnis genutzt (seit 08:12)'),
        findsOneWidget,
        reason: 'nur Gedächtnis: ruhigerer Text',
      );
      c
          .read(agentControllerProvider.notifier)
          .seed(
            ConversationState(privateSince: testNow, privateByRequest: true),
          );
      await tester.pumpAndSettle();
      expect(find.text('Unterhaltung privat (seit 08:12)'), findsOneWidget);

      await tester.tap(find.text('Neues Gespräch'));
      await settle(tester);
      expect(find.byType(PrivateConversationBanner), findsNothing);
      expect(c.read(agentControllerProvider).privateSince, isNull);
    });

    testWidgets('während einer Anfrage ist „Neues Gespräch“ gesperrt', (
      tester,
    ) async {
      final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
      final c = await _pumpMain(tester, env);
      c
          .read(agentControllerProvider.notifier)
          .seed(ConversationState(privateSince: testNow, running: true));
      await tester.pump();
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Neues Gespräch'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Overlay zeigt den Hinweis, mit Touch-Ziel ≥ 44', (
      tester,
    ) async {
      var ended = 0;
      final handle = tester.ensureSemantics();
      setView(tester, screenSize);
      await tester.pumpWidget(
        themed(
          Scaffold(
            body: SizedBox(
              height: WSize.overlaySheet,
              child: OverlaySheet(
                providerName: 'Phala GLM',
                privacy: PrivacyLevel.tee,
                exchange: const OverlayExchange(request: 'Wie geht es Anna?'),
                mic: MicState.idle,
                levels: const [],
                onMic: () {},
                onClose: () {},
                onKeyboard: () {},
                onUndo: (_) {},
                privateSince: testNow,
                onNewConversation: () => ended++,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Unterhaltung privat (seit 08:12)'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.tap(find.text('Neues Gespräch'));
      expect(ended, 1);
      handle.dispose();
    });

    testWidgets('Eskalationsrückfrage nennt die privaten Teile', (
      tester,
    ) async {
      final question = EscalationQuestion(
        EscalationConfirmationRequired(
          fromProfile: 'phala',
          toProfile: 'claude',
          reason: EscalationReason.userRequested,
          respond: (_) {},
        ),
        fromName: 'Phala GLM',
        toName: 'Claude API',
      );
      Future<void> pump(DateTime? since) => pumpComponent(tester, [
        confirmationCardFor(
          AppLocalizationsDe(),
          question,
          (_) {},
          privateSince: since,
        ),
      ]);
      await pump(null);
      expect(find.textContaining('privaten Teile'), findsNothing);
      await pump(testNow);
      expect(
        find.textContaining(
          privateEscalationHint(AppLocalizationsDe(), testNow, 'Claude API'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('(seit 08:12)'), findsOneWidget);
      await pumpComponent(tester, [
        confirmationCardFor(
          AppLocalizationsDe(),
          question,
          (_) {},
          privateSince: testNow,
          privateByRequest: false,
        ),
      ]);
      expect(find.textContaining('nutzt dein Gedächtnis'), findsOneWidget);
    });
  });

  group('Hinweis auf die neue Regel „Privat“', () {
    testWidgets('ohne gespeicherten Hinweis keine Karte', (tester) async {
      final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
      await _pumpMain(tester, env);
      expect(find.byType(PrivateRuleNoticeCard), findsNothing);
      expect(find.textContaining('Neu: Regel „Privat“'), findsNothing);
    });

    for (final open in [true, false]) {
      testWidgets(open ? 'Routing ansehen' : 'Verstanden', (tester) async {
        final env = TestEnv(
          providerConfig: scripted(FakeLlmProvider(const [])),
        );
        await env.storage.settings.set(
          RoutingSettings.privateRuleNotice,
          'Phala GLM',
        );
        await _pumpMain(tester, env);
        expect(
          find.text(privateRuleNoticeText(AppLocalizationsDe(), 'Phala GLM')),
          findsOneWidget,
        );
        await tester.tap(find.text(open ? 'Routing ansehen' : 'Verstanden'));
        await settle(tester);
        expect(
          find.byType(RoutingScreen),
          open ? findsOneWidget : findsNothing,
        );
        expect(
          await env.storage.settings.get(RoutingSettings.privateRuleNotice),
          isNull,
          reason: 'nur einmal',
        );
        if (open) {
          tester.state<NavigatorState>(find.byType(Navigator)).pop();
          await settle(tester);
        }
        expect(
          find.text(privateRuleNoticeText(AppLocalizationsDe(), 'Phala GLM')),
          findsNothing,
        );
      });
    }
  });

  group('Regel im ProviderChip', () {
    test('Routed setzt die Regel, Standard und Eskalation nicht', () {
      final r = ConversationReducer(nameOf: (id) => id);
      var s = r.apply(
        ConversationState.empty,
        const Routed(
          profileId: 'claude',
          modelId: 'opus',
          reason: 'Starkes Modell',
        ),
      );
      expect(s.activeRule, 'Starkes Modell');
      s = r.apply(
        s,
        const Escalated(
          fromProfile: 'claude',
          toProfile: 'phala',
          reason: EscalationReason.userRequested,
        ),
      );
      expect(s.activeRule, isNull);
      expect(s.entries.whereType<EscalationEntry>(), hasLength(1));
      s = r.apply(
        s,
        const Routed(profileId: 'phala', modelId: 'glm', reason: 'Standard'),
      );
      expect(s.activeRule, isNull);
      expect(
        providerLabel('Claude API', 'Starkes Modell'),
        'Claude API · Starkes Modell',
      );
      expect(providerLabel('Claude API', null), 'Claude API');
    });

    testWidgets('Hauptbildschirm: Name und Regel im Chip', (tester) async {
      final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
      final c = await _pumpMain(tester, env);
      c
          .read(agentControllerProvider.notifier)
          .seed(
            ConversationState(
              activeProfileId: 'claude',
              activeRule: 'Starkes Modell',
            ),
          );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(ProviderChip, 'Claude Haiku · Starkes Modell'),
        findsOneWidget,
      );
    });
  });

  group('Gedächtnis: Untergrenze je Eintrag', () {
    testWidgets('angezeigt und mit Bestätigung aufhebbar', (tester) async {
      final env = TestEnv();
      final private = await env.storage.memory.save(
        'Anna hat Diabetes',
        category: StoredMemoryCategory.person,
        source: 'user',
        privacyFloor: PrivacyLevel.tee,
      );
      await env.storage.memory.save(
        'Lieblingsfarbe Blau',
        category: StoredMemoryCategory.preference,
        source: 'user',
      );
      await pumpPage(tester, env, const MemoryScreen());
      expect(find.text('Person · privat, nur ab TEE'), findsOneWidget);
      expect(find.text('Vorliebe'), findsOneWidget);

      Future<void> lift({required bool confirmIt}) async {
        await tester.tap(find.text('Anna hat Diabetes'));
        await tester.pumpAndSettle();
        expect(
          find.text('Aus einer privaten Anfrage: geht nur an Provider ab TEE.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Untergrenze aufheben'));
        await tester.pumpAndSettle();
        expect(find.text('Untergrenze aufheben?'), findsOneWidget);
        await tester.tap(find.text(confirmIt ? 'Aufheben' : 'Abbrechen'));
        await settle(tester);
      }

      await lift(confirmIt: false);
      expect(
        (await env.storage.memory.get(private.id))!.privacyFloor,
        PrivacyLevel.tee,
      );
      await lift(confirmIt: true);
      expect((await env.storage.memory.get(private.id))!.privacyFloor, isNull);
      expect(find.text('Person'), findsOneWidget);
      expect(find.textContaining('privat, nur ab'), findsNothing);
    });

    testWidgets('ohne Untergrenze kein Knopf', (tester) async {
      final env = TestEnv();
      await env.storage.memory.save(
        'Lieblingsfarbe Blau',
        category: StoredMemoryCategory.preference,
        source: 'user',
      );
      await pumpPage(tester, env, const MemoryScreen());
      await tester.tap(find.text('Lieblingsfarbe Blau'));
      await tester.pumpAndSettle();
      expect(find.text('Untergrenze aufheben'), findsNothing);
    });
  });
}
