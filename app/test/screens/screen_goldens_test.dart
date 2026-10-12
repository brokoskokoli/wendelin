@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart';

/// Sample conversation of docs/design/screens/hauptbildschirm.
ConversationState mainScreenSample() => ConversationState(
  entries: [
    SessionStartEntry('s', testNow),
    const UserEntry('u1', 'Wie wird das Meer morgen früh?'),
    const ToolEntry(
      't1',
      toolName: 'weather__marine_forecast',
      phase: ToolPhase.done,
    ),
    const AssistantTextEntry(
      'a1',
      'Ruhig: 0,4 m Welle, Dünung aus Südwest, Wasser 19 °C. '
          'Gute Bedingungen fürs Tauchen.',
    ),
    const UserEntry(
      'u2',
      'Claude, fass meine Notizen zum Tauchkurs zusammen und häng es an '
          'die Tagesnotiz.',
    ),
    const EscalationEntry('x', 'an Claude Sonnet übergeben'),
    const ToolEntry(
      't2',
      toolName: 'obsidian__search_notes',
      phase: ToolPhase.done,
    ),
    const ToolEntry(
      't3',
      toolName: 'obsidian__append_daily_note',
      phase: ToolPhase.done,
    ),
    const AssistantTextEntry(
      'a2',
      'Fünf Punkte aus drei Notizen, angehängt unter „Tauchen“ in der '
          'Tagesnotiz vom 12.10.',
    ),
  ],
  activeProfileId: 'phala',
);

Future<ProviderContainer> pumpMain(WidgetTester tester, TestEnv env) async {
  await env.storage.usage.record(
    sessionId: 's',
    profileId: 'phala',
    modelId: 'glm',
    usage: Usage.zero,
    costMicros: 30000,
  );
  setView(tester, screenSize);
  await tester.pumpWidget(
    RepaintBoundary(
      key: goldenKey,
      child: env.app(home: const MainScreen(restoreSession: false)),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(MainScreen)));
}

TestEnv phalaEnv() => TestEnv(
  providerConfig: scripted(
    FakeLlmProvider(const []),
    id: 'phala',
    name: 'Phala · GLM klein',
    privacy: PrivacyLevel.tee,
  ),
);

void main() {
  testWidgets('Hauptbildschirm mit Beispieldaten', (tester) async {
    final c = await pumpMain(tester, phalaEnv());
    c.read(agentControllerProvider.notifier).seed(mainScreenSample());
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/hauptbildschirm.png'),
    );
  });

  testWidgets('Bestätigung als Bottom Sheet', (tester) async {
    final env = TestEnv(
      providerConfig: scripted(FakeLlmProvider(const []), name: 'Claude Haiku'),
    );
    final c = await pumpMain(tester, env);
    final controller = c.read(agentControllerProvider.notifier);
    final call = ToolCallBlock(
      id: 'c1',
      name: 'calendar__delete_event',
      argumentsJson: '{"event_id":"e1"}',
    );
    controller.seed(
      ConversationState(
        entries: [
          SessionStartEntry('s', testNow),
          const UserEntry('u', 'Lösch den Zahnarzttermin am Donnerstag.'),
          const ToolEntry(
            'c1',
            toolName: 'calendar__delete_event',
            phase: ToolPhase.awaitingConfirmation,
          ),
        ],
        running: true,
        activeProfileId: 'claude',
        pending: ToolQuestion(
          ConfirmationRequired(
            call: call,
            description:
                'Termin ‚Zahnarzt Dr. Weber‘ Do 15.10. 08:30–09:15 löschen',
            respond: (_) {},
          ),
          request: 'Lösch den Zahnarzttermin am Donnerstag.',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/bestaetigung.png'),
    );
  });
}
