import 'package:flutter/gestures.dart' show kLongPressTimeout, kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/profiles.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart'
    show TriggerKind, VoiceState;

import '../settings/integrations_screen_test.dart' show settle;
import '../settings/other_screens_test.dart' show profile;
import '../support/test_env.dart';
import '../ui/helpers.dart';
import '../voice/voice_controller_test.dart' show fakeVoice, utterance;

const _sheetTitle = 'Agent wechseln';

Future<void> _openSheet(WidgetTester tester) async {
  final g = await tester.startGesture(tester.getCenter(_chip));
  await tester.pump(kLongPressTimeout);
  await settle(tester);
  await g.up();
}

Future<(ProviderContainer, List<String>)> _pump(
  WidgetTester tester, {
  int profiles = 2,
  List<Override> overrides = const [],
}) async {
  final env = TestEnv(storedProfiles: true, extraOverrides: overrides);
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

Finder get _target => find.byKey(const ValueKey('quickSwitchTarget'));

final _justBefore = kLongPressTimeout - const Duration(milliseconds: 1);

bool _hasHistory(ProviderContainer c) =>
    c.read(agentControllerProvider).entries.any((e) => e is! SessionStartEntry);

void main() {
  testWidgets('Halten knapp unter der Long-Press-Dauer: nichts passiert', (
    tester,
  ) async {
    final (_, haptics) = await _pump(tester);
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(_justBefore);
    await tester.pump();
    expect(haptics, isEmpty);
    expect(find.text(_sheetTitle), findsNothing);
    await g.up();
  });

  testWidgets('Langer Druck öffnet das Popup zusammen mit der Vibration', (
    tester,
  ) async {
    final (_, haptics) = await _pump(tester);
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(kLongPressTimeout);
    await tester.pump();
    expect(haptics, ['HapticFeedbackType.mediumImpact']);
    expect(find.text(_sheetTitle), findsOneWidget);
    await g.up();
    await settle(tester);
    expect(haptics, hasLength(1));
    expect(find.text(_sheetTitle), findsOneWidget);
    expect(find.text('Profil a'), findsWidgets);
    expect(find.text('Profil b'), findsOneWidget);
    expect(find.text('Profil c'), findsNothing);
    expect(find.byType(CheckStatusIcon), findsOneWidget);
  });

  testWidgets('Weiter halten und loslassen lässt das Popup offen', (
    tester,
  ) async {
    final (c, haptics) = await _pump(tester);
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(kLongPressTimeout);
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));
    await g.up();
    await settle(tester);
    expect(find.text(_sheetTitle), findsOneWidget);
    expect(haptics, hasLength(1));
    expect((await c.read(profilesProvider.future)).defaultId, 'a');
    expect(_hasHistory(c), isTrue);
  });

  testWidgets('Loslassen vor der Long-Press-Dauer bricht ab', (tester) async {
    final (c, haptics) = await _pump(tester);
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(haptics, isEmpty);
    expect(find.text(_sheetTitle), findsNothing);
    expect(_hasHistory(c), isTrue);
  });

  testWidgets('Wegziehen vor der Long-Press-Dauer bricht ab', (tester) async {
    final (_, haptics) = await _pump(tester);
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(const Duration(milliseconds: 300));
    await g.moveBy(const Offset(0, kTouchSlop + 1));
    await tester.pump(const Duration(seconds: 3));
    expect(haptics, isEmpty);
    expect(find.text(_sheetTitle), findsNothing);
    await g.up();
  });

  testWidgets('Auswahl setzt den Standard und leert den Chat', (tester) async {
    final (c, _) = await _pump(tester);
    expect(_hasHistory(c), isTrue);
    await _openSheet(tester);
    await tester.tap(find.text('Profil b'));
    await settle(tester);
    expect((await c.read(profilesProvider.future)).defaultId, 'b');
    expect(_hasHistory(c), isFalse);
    expect(find.text(_sheetTitle), findsNothing);
    expect(find.text('Profil b'), findsOneWidget, reason: 'Chip folgt');
  });

  testWidgets('Auswahl des aktuellen Agenten ändert nichts', (tester) async {
    final (c, _) = await _pump(tester);
    await _openSheet(tester);
    await tester.tap(find.text('Profil a').last);
    await settle(tester);
    expect((await c.read(profilesProvider.future)).defaultId, 'a');
    expect(_hasHistory(c), isTrue);
  });

  testWidgets('Schließen ohne Auswahl ändert nichts', (tester) async {
    final (c, _) = await _pump(tester);
    await _openSheet(tester);
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
    final handle = tester.ensureSemantics();
    final (_, haptics) = await _pump(tester, profiles: 1);
    final g = await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(const Duration(seconds: 3));
    expect(haptics, isEmpty);
    expect(find.text(_sheetTitle), findsNothing);
    await g.up();
    final data = tester.getSemantics(_target).getSemanticsData();
    expect(data.customSemanticsActionIds, anyOf(isNull, isEmpty));
    expect(data.hasAction(SemanticsAction.longPress), isFalse);
    handle.dispose();
  });

  testWidgets('Semantics-Aktion öffnet das Popup direkt', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    final node = tester.getSemantics(_target);
    final ids = node.getSemanticsData().customSemanticsActionIds!;
    final id = ids.firstWhere(
      (i) => CustomSemanticsAction.getAction(i)?.label == _sheetTitle,
    );
    tester.semantics.performAction(
      find.semantics.byAction(SemanticsAction.customAction),
      SemanticsAction.customAction,
      args: id,
    );
    await settle(tester);
    expect(find.text(_sheetTitle), findsOneWidget);
    handle.dispose();
  });

  testWidgets('Auswahl beendet zuerst die laufende Sprachaufnahme', (
    tester,
  ) async {
    final (c, _) = await _pump(
      tester,
      overrides: [
        activeVoiceProvider.overrideWith(
          (ref) async => fakeVoice(
            audio: FakeAudioInput(
              frames: utterance(),
              frameInterval: const Duration(seconds: 1),
            ),
            script: const [],
          ),
        ),
      ],
    );
    await c
        .read(voiceControllerProvider.notifier)
        .start(TriggerKind.pushToTalk);
    await tester.pump();
    expect(c.read(voiceControllerProvider).phase, VoiceState.listening);
    await _openSheet(tester);
    expect(c.read(voiceControllerProvider).phase, VoiceState.listening);
    await tester.tap(find.text('Profil b'));
    await settle(tester);
    expect(c.read(voiceControllerProvider).phase, VoiceState.idle);
    expect((await c.read(profilesProvider.future)).defaultId, 'b');
  });

  testWidgets('Läuft nach dem Öffnen eine Anfrage, bleibt alles', (
    tester,
  ) async {
    final (c, _) = await _pump(tester);
    await _openSheet(tester);
    c
        .read(agentControllerProvider.notifier)
        .seed(ConversationState(running: true));
    await tester.pump();
    await tester.tap(find.text('Profil b'));
    await settle(tester);
    expect((await c.read(profilesProvider.future)).defaultId, 'a');
    expect(c.read(agentControllerProvider).running, isTrue);
  });

  testWidgets('Entfernen während des Haltens lässt keinen Timer zurück', (
    tester,
  ) async {
    await _pump(tester);
    await tester.startGesture(tester.getCenter(_chip));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    expect(find.text(_sheetTitle), findsNothing);
  });
}
