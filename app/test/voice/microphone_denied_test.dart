// Mikrofon-Berechtigung verweigert (WP18-Review N12/N14, WP19): erst die
// Erklärung, dann kein Start – auf dem Hauptbildschirm und im Overlay.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/voice/microphone_access.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';

import '../overlay/assistant_overlay_test.dart'
    show FakeAssistantPlatform, pumpOverlay;
import '../screens/main_screen_test.dart' show pumpApp, pumpUntil;
import '../support/test_env.dart';
import 'voice_controller_test.dart' show fakeVoice, utterance;

const _noAccess = 'Ohne Mikrofon-Zugriff geht nur Text.';

TestEnv _env(FakeAudioInput audio, {required bool overlay}) => TestEnv(
  providerConfig: scripted(FakeLlmProvider(const [])),
  extraOverrides: [
    if (!overlay) ...[
      voiceReadyProvider.overrideWithValue(true),
      activeVoiceProvider.overrideWith((ref) async => fakeVoice(audio: audio)),
    ],
  ],
);

FakeAudioInput _audio() => FakeAudioInput(frames: utterance());

void main() {
  group('Hauptbildschirm', () {
    testWidgets('„Nicht jetzt“: Erklärung, kein Android-Dialog, kein Start', (
      tester,
    ) async {
      final audio = _audio();
      final env = _env(audio, overlay: false);
      env.microphone.granted = false;
      await pumpApp(tester, env);
      await tester.pump();

      await tester.tap(find.byType(MicButton));
      await pumpUntil(tester, find.text('Mikrofon erlauben?'));
      expect(
        find.text(microphoneExplanation(AppLocalizationsDe())),
        findsOneWidget,
      );
      await tester.tap(find.text('Nicht jetzt'));
      await pumpUntil(tester, find.text(_noAccess));

      // Nur still nachgesehen (Erklärung und frühes Mikrofon, WP30),
      // Android nie gefragt; das Mikrofon blieb zu.
      expect(env.microphone.requests, everyElement(isFalse));
      expect(env.microphone.starts, 0);
      expect(audio.startCount, 0);
      expect(
        tester.widget<MicButton>(find.byType(MicButton)).state,
        MicState.idle,
      );
    });

    testWidgets('„Erlauben“, Android verweigert: Hinweis, kein Start', (
      tester,
    ) async {
      final audio = _audio();
      final env = _env(audio, overlay: false);
      env.microphone.granted = false;
      await pumpApp(tester, env);
      await tester.pump();

      await tester.tap(find.byType(MicButton));
      await pumpUntil(tester, find.text('Erlauben'));
      await tester.tap(find.text('Erlauben'));
      await pumpUntil(tester, find.textContaining('Apps → Wendelin erlauben'));
      await pumpUntil(tester, find.text(_noAccess));
      // Android genau einmal gefragt (nach „Erlauben“), nie aufgenommen.
      expect(env.microphone.requests.where((r) => r), hasLength(1));
      expect(env.microphone.requests.last, isTrue);
      expect(env.microphone.starts, 0);
      expect(audio.startCount, 0);
    });
  });

  group('Hinweis über der Eingabezeile (WP32)', () {
    Future<(TestEnv, List<int>)> denied(WidgetTester tester) async {
      final opened = <int>[];
      final audio = _audio();
      final base = _env(audio, overlay: false);
      final env = TestEnv(
        providerConfig: scripted(FakeLlmProvider(const [])),
        extraOverrides: [
          ...base.extraOverrides,
          appSettingsOpenerProvider.overrideWithValue(
            () async => opened.add(1),
          ),
        ],
      );
      env.microphone.granted = false;
      await pumpApp(tester, env);
      await tester.pump();
      await tester.tap(find.byType(MicButton));
      await pumpUntil(tester, find.text('Nicht jetzt'));
      await tester.tap(find.text('Nicht jetzt'));
      await pumpUntil(tester, find.byType(MicrophoneNotice));
      return (env, opened);
    }

    testWidgets('„Nicht jetzt“: Karte mit „Erlauben“, Erlauben fragt Android', (
      tester,
    ) async {
      final (env, _) = await denied(tester);
      expect(
        find.descendant(
          of: find.byType(MicrophoneNotice),
          matching: find.text(_noAccess),
        ),
        findsOneWidget,
      );
      final allow = find.widgetWithText(OutlinedButton, 'Erlauben');
      expect(
        tester.getSize(allow).height,
        greaterThanOrEqualTo(WSize.touchMin),
      );
      // Above the input row.
      expect(
        tester.getBottomLeft(find.byType(MicrophoneNotice)).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy),
      );
      env.microphone.granted = true;
      await tester.tap(allow);
      await tester.pump();
      await tester.pump();
      expect(env.microphone.requests.last, isTrue, reason: 'Android fragt');
      expect(find.byType(MicrophoneNotice), findsNothing);
      expect(find.text(_noAccess), findsNothing);
    });

    testWidgets('Android verweigert: „Android-Einstellungen“, nach Rückkehr '
        'erlaubt verschwindet die Karte', (tester) async {
      final (env, opened) = await denied(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Erlauben'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(MicrophoneNotice), findsOneWidget);
      expect(
        find.text(microphoneSettingsHint(AppLocalizationsDe())),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Android-Einstellungen'),
      );
      await tester.pump();
      expect(opened, [1]);

      env.microphone.granted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(find.byType(MicrophoneNotice), findsNothing);
    });
  });

  group('Overlay', () {
    testWidgets('beim Öffnen: Erklärung, „Nicht jetzt“, kein Start', (
      tester,
    ) async {
      final audio = _audio();
      final env = _env(audio, overlay: true);
      env.microphone.granted = false;
      final platform = FakeAssistantPlatform();
      final c = await pumpOverlay(
        tester,
        env,
        platform,
        voice: fakeVoice(audio: audio),
      );

      await pumpUntil(tester, find.text('Mikrofon erlauben?'));
      expect(
        find.text(microphoneExplanation(AppLocalizationsDe())),
        findsOneWidget,
      );
      await tester.tap(find.text('Nicht jetzt'));
      await pumpUntil(tester, find.text(_noAccess));
      expect(env.microphone.requests, everyElement(isFalse));
      expect(env.microphone.starts, 0);
      // Das Mikrofon wird früh geöffnet (B11); die echte Eingabe prüft die
      // Berechtigung und nimmt ohne sie nichts auf (env.microphone.starts).
      expect(audio.isRunning, isFalse);
      expect(c.read(voiceControllerProvider).active, isFalse);
      // Das Overlay bleibt offen (Tippen oder Tastatur gehen weiter).
      expect(platform.finished, 0);
    });
  });
}
