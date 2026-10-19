import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/profiles.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/ui/screens/quick_switch.dart';

import '../settings/integrations_screen_test.dart' show settle;
import '../settings/other_screens_test.dart' show profile;
import '../support/test_env.dart';
import '../ui/helpers.dart';

const _sheetTitle = 'Agent wechseln';

Future<(ProviderContainer, List<String>)> _pump(
  WidgetTester tester, {
  int profiles = 2,
}) async {
  final env = TestEnv(storedProfiles: true);
  for (final id in ['a', 'b', 'c'].take(profiles)) {
    await env.storage.providerProfiles.save(profile(id));
  }
  await env.storage.providerProfiles.setDefault('a');
  setView(tester, screenSize);
  await tester.pumpWidget(
    env.app(home: const MainScreen(restoreSession: false)),
  );
  await settle(tester);
  final haptics = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  final c = ProviderScope.containerOf(tester.element(find.byType(MainScreen)));
  c.read(agentControllerProvider.notifier).addNotice('Hinweis');
  await tester.pump();
  return (c, haptics);
}

Finder get _chip => find.text('Profil a');

Color? _markColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.byKey(const ValueKey('quickSwitchMark')),
  );
  return ((box.decoration as BoxDecoration).border! as Border).top.color;
}

bool _hasHistory(ProviderContainer c) =>
    c.read(agentControllerProvider).entries.any((e) => e is! SessionStartEntry);

void main() {
  testWidgets('Halten markiert mit Vibration, nach 2 s öffnet das Popup', (
    tester,
  ) async {
    final (_, haptics) = await _pump(tester);
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(const Duration(milliseconds: 200));
    expect(haptics, isEmpty);
    expect(_markColor(tester), Colors.transparent);
    await tester.pump(const Duration(milliseconds: 400));
    expect(haptics, ['HapticFeedbackType.mediumImpact']);
    expect(_markColor(tester), isNot(Colors.transparent));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text(_sheetTitle), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.text(_sheetTitle), findsOneWidget);
    expect(find.text('Profil a'), findsWidgets);
    expect(find.text('Profil b'), findsOneWidget);
    expect(find.text('Profil c'), findsNothing);
    expect(find.byType(CheckStatusIcon), findsOneWidget);
    await g.up();
  });

  testWidgets('Loslassen vor 2 s bricht ab: keine Markierung, kein Popup', (
    tester,
  ) async {
    final (c, _) = await _pump(tester);
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(_markColor(tester), isNot(Colors.transparent));
    await g.up();
    await tester.pump();
    expect(_markColor(tester), Colors.transparent);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(_sheetTitle), findsNothing);
    expect(_hasHistory(c), isTrue);
  });

  testWidgets('Wegziehen bricht ab', (tester) async {
    await _pump(tester);
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(0, 80));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(_sheetTitle), findsNothing);
    await g.up();
  });

  testWidgets('Auswahl setzt den Standard und leert den Chat', (tester) async {
    final (c, _) = await _pump(tester);
    expect(_hasHistory(c), isTrue);
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(quickSwitchHold);
    await settle(tester);
    await g.up();
    await tester.tap(find.text('Profil b'));
    await settle(tester);
    expect((await c.read(profilesProvider.future)).defaultId, 'b');
    expect(_hasHistory(c), isFalse);
    expect(find.text(_sheetTitle), findsNothing);
    expect(find.text('Profil b'), findsOneWidget, reason: 'Chip folgt');
  });

  testWidgets('Auswahl des aktuellen Agenten ändert nichts', (tester) async {
    final (c, _) = await _pump(tester);
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(quickSwitchHold);
    await settle(tester);
    await g.up();
    await tester.tap(find.text('Profil a').last);
    await settle(tester);
    expect((await c.read(profilesProvider.future)).defaultId, 'a');
    expect(_hasHistory(c), isTrue);
  });

  testWidgets('Schließen ohne Auswahl ändert nichts', (tester) async {
    final (c, _) = await _pump(tester);
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(quickSwitchHold);
    await settle(tester);
    await g.up();
    await tester.tapAt(const Offset(195, 40));
    await settle(tester);
    expect(find.text(_sheetTitle), findsNothing);
    expect((await c.read(profilesProvider.future)).defaultId, 'a');
    expect(_hasHistory(c), isTrue);
  });

  testWidgets('während einer Anfrage gesperrt', (tester) async {
    final (c, haptics) = await _pump(tester);
    c
        .read(agentControllerProvider.notifier)
        .seed(ConversationState(running: true));
    await tester.pump();
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(const Duration(seconds: 3));
    expect(haptics, isEmpty);
    expect(find.text(_sheetTitle), findsNothing);
    await g.up();
  });

  testWidgets('mit nur einem Profil nicht möglich', (tester) async {
    await _pump(tester, profiles: 1);
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(_sheetTitle), findsNothing);
    await g.up();
  });

  testWidgets('Semantics-Aktion öffnet das Popup direkt', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    final node = tester.getSemantics(
      find.byKey(const ValueKey('quickSwitchMark')),
    );
    expect(node.getSemanticsData().customSemanticsActionIds, isNotNull);
    tester.semantics.longPress(
      find.semantics.byAction(SemanticsAction.longPress),
    );
    await settle(tester);
    expect(find.text(_sheetTitle), findsOneWidget);
    handle.dispose();
  });
}
