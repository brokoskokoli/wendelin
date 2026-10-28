// Renders the README/website screenshots (WP169, part C). Not part of the
// gate: tag `screenshots`, started by `tool/make_screenshots.sh`. The real
// screens are rendered by the widget test engine (no emulator) with
// English UI and invented sample content; nothing is compared.
@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/ui/onboarding/onboarding_screen.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/ui/settings/settings_screen.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../settings/integrations_screen_test.dart' show settle;
import '../support/test_env.dart';
import '../ui/helpers.dart';

/// Output folder (PNG, @3x); set by `tool/make_screenshots.sh`.
final _dir = Platform.environment['SCREENSHOT_DIR'];
final _out = _dir ?? 'build/screenshots';

/// Skip reason outside `tool/make_screenshots.sh` (gate, CI).
final String? _skip = _dir == null ? 'only via tool/make_screenshots.sh' : null;

const _dpr = 3.0;

TestEnv _env({Set<String>? enabled, bool onboardingDone = true}) => TestEnv(
  providerConfig: onboardingDone
      ? scripted(
          FakeLlmProvider(const []),
          id: 'phala',
          name: 'Phala · GLM',
          privacy: PrivacyLevel.tee,
        )
      : null,
  startup: StartupSettings(
    uiLanguage: 'en',
    // The app defaults speech to German on every fresh install
    // (StartupSettings.language), so the shot picks English explicitly.
    language: 'en',
    onboardingDone: onboardingDone,
    enabledIntegrations:
        enabled ?? const {'calendar', 'memory', 'web', 'alarms', 'clipboard'},
  ),
  storedProfiles: !onboardingDone,
);

Future<void> _show(
  WidgetTester tester,
  TestEnv env,
  Widget home, {
  Size? size,
}) async {
  setView(tester, size ?? screenSize, dpr: _dpr);
  await tester.pumpWidget(
    RepaintBoundary(
      key: goldenKey,
      child: env.app(home: home),
    ),
  );
  await settle(tester);
}

Future<void> _save(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(goldenKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_out/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

ProviderContainer _container(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen)));

void main() {
  testWidgets('conversation', skip: _skip != null, (tester) async {
    final env = _env();
    await _show(tester, env, const MainScreen(restoreSession: false));
    _container(tester, MainScreen)
        .read(agentControllerProvider.notifier)
        .seed(
          ConversationState(
            entries: [
              SessionStartEntry('s', testNow),
              const UserEntry('u1', 'What is on my calendar tomorrow?'),
              const ToolEntry(
                't1',
                toolName: 'calendar__list_events',
                phase: ToolPhase.done,
              ),
              const AssistantTextEntry(
                'a1',
                'Two things: a team sync at 10:00 and a dentist '
                    'appointment at 15:30.',
              ),
              const UserEntry(
                'u2',
                'Move the sync to 11:00 and set a timer for 15 minutes.',
              ),
              const ToolEntry(
                't2',
                toolName: 'calendar__update_event',
                phase: ToolPhase.done,
              ),
              const ToolEntry(
                't3',
                toolName: 'alarms__set_timer',
                phase: ToolPhase.done,
              ),
              const AssistantTextEntry(
                'a2',
                'Done. The team sync now starts at 11:00 and your 15 minute '
                    'timer is running.',
              ),
            ],
            activeProfileId: 'phala',
          ),
        );
    await tester.pumpAndSettle();
    await _save(tester, 'conversation');
  });

  testWidgets('confirmation', skip: _skip != null, (tester) async {
    final env = _env();
    await _show(tester, env, const MainScreen(restoreSession: false));
    final call = ToolCallBlock(
      id: 'c1',
      name: 'calendar__delete_event',
      argumentsJson: '{"event_id":"e1"}',
    );
    _container(tester, MainScreen)
        .read(agentControllerProvider.notifier)
        .seed(
          ConversationState(
            entries: [
              SessionStartEntry('s', testNow),
              const UserEntry(
                'u',
                'Delete the dentist appointment on Thursday.',
              ),
              const ToolEntry(
                'c1',
                toolName: 'calendar__delete_event',
                phase: ToolPhase.awaitingConfirmation,
              ),
            ],
            running: true,
            activeProfileId: 'phala',
            pending: ToolQuestion(
              ConfirmationRequired(
                call: call,
                description:
                    "Delete event 'Dentist, Dr. Fischer' on Thu 15 Oct, "
                    '08:30–09:15?',
                respond: (_) {},
              ),
              request: 'Delete the dentist appointment on Thursday.',
            ),
          ),
        );
    await tester.pumpAndSettle();
    await _save(tester, 'confirmation');
  });

  testWidgets('settings', skip: _skip != null, (tester) async {
    // Shorter view: ends below the last menu card, so the "Development"
    // section (demo mode) is not cut off at the bottom.
    await _show(
      tester,
      _env(),
      const SettingsScreen(),
      size: Size(screenSize.width, 748),
    );
    await _save(tester, 'settings');
  });

  testWidgets('onboarding', skip: _skip != null, (tester) async {
    final env = _env(onboardingDone: false);
    setView(tester, screenSize, dpr: _dpr);
    await tester.pumpWidget(RepaintBoundary(key: goldenKey, child: env.app()));
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await _save(tester, 'onboarding');
  });
}
