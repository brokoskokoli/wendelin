// WP93: a wake word hit with the chat visible continues the conversation in
// the chat; settings open, app paused or device locked leave it to the
// overlay.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/wake_settings.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/platform/wake/wake_platform.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/wake_chat.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../overlay/assistant_overlay_test.dart' show FakeAssistantPlatform;
import '../support/test_env.dart';
import '../ui/helpers.dart';
import '../voice/voice_controller_test.dart' show fakeVoice;
import 'main_screen_test.dart' show containerOf, pumpApp;

/// Stand-in for the Kotlin side of the wake word service (main app).
final class FakeWakePlatform extends WakePlatform {
  Future<bool> Function()? handler;
  final visible = <bool>[];
  int done = 0;

  @override
  set onWakeHit(Future<bool> Function()? h) => handler = h;

  @override
  Future<bool> Function()? get onWakeHit => handler;

  @override
  Future<void> setChatVisible({required bool visible}) async =>
      this.visible.add(visible);

  @override
  Future<void> chatDone() async => done++;

  /// The service asks the main engine.
  Future<bool> hit() => handler?.call() ?? Future.value(false);
}

void main() {
  late FakeWakePlatform wake;
  late FakeAssistantPlatform assistant;
  final logLines = <String>[];
  late void Function(String) savedSink;
  setUp(() {
    logLines.clear();
    savedSink = voiceLogSink;
    voiceLogSink = logLines.add;
  });
  tearDown(() => voiceLogSink = savedSink);

  Future<void> pump(WidgetTester tester, {bool handoff = true}) async {
    wake = FakeWakePlatform();
    assistant = FakeAssistantPlatform();
    if (handoff) {
      assistant.wakeHandoff = Int16List.fromList(List.filled(8000, 300));
    }
    final env = TestEnv(
      providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('ok')])),
      extraOverrides: [
        wakePlatformProvider.overrideWithValue(wake),
        assistantPlatformProvider.overrideWithValue(assistant),
        voiceReadyProvider.overrideWithValue(true),
        wakeConfirmToneProvider.overrideWithValue(() async {}),
        activeVoiceProvider.overrideWith(
          (ref) async => fakeVoice(
            script: const [
              Transcript(text: 'Wie wird das Wetter?', language: 'de'),
            ],
          ),
        ),
      ],
    );
    await pumpApp(tester, env);
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<bool> askHit(WidgetTester tester) async {
    bool? answer;
    unawaited(wake.hit().then((v) => answer = v));
    await pumpUntil(tester, () => answer != null);
    return answer!;
  }

  testWidgets(
    'Chat sichtbar: der Chat hört zu, danach hört der Dienst wieder',
    (tester) async {
      await pump(tester);
      expect(wake.visible, [true]);
      final c = containerOf(tester);
      final triggers = <TriggerKind?>[];
      c.listen(voiceControllerProvider.select((v) => v.trigger), (_, t) {
        triggers.add(t);
      });
      expect(await askHit(tester), isTrue);
      await pumpUntil(tester, () => wake.done > 0);
      expect(triggers, contains(TriggerKind.wakeWord));
      expect(assistant.wakeTakes, 1);
      expect(wake.done, 1);
    },
  );

  testWidgets('Einstellungen offen: Overlay, der Chat nimmt nichts', (
    tester,
  ) async {
    await pump(tester);
    unawaited(
      Navigator.of(tester.element(find.byType(MainScreen))).push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Zwei'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(wake.visible, [true, false]);
    // Race: the service still holds an old flag, the chat looks again.
    expect(await askHit(tester), isFalse);
    expect(assistant.wakeTakes, 0);
    expect(containerOf(tester).read(voiceControllerProvider).active, isFalse);
  });

  testWidgets('Dialog über dem Chat: Overlay', (tester) async {
    await pump(tester);
    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(MainScreen)),
        builder: (_) => const AlertDialog(title: Text('Frage')),
      ),
    );
    await tester.pumpAndSettle();
    expect(await askHit(tester), isFalse);
    expect(assistant.wakeTakes, 0);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    expect(wake.visible.last, isTrue);
  });

  testWidgets('App pausiert: Overlay; wieder da: Chat', (tester) async {
    await pump(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(wake.visible.last, isFalse);
    expect(await askHit(tester), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(wake.visible.last, isTrue);
    expect(await askHit(tester), isTrue);
  });

  testWidgets('Gerät gesperrt: Overlay', (tester) async {
    await pump(tester);
    assistant.locked = true;
    expect(await askHit(tester), isFalse);
    expect(assistant.wakeTakes, 0);
  });

  testWidgets('Pre-Roll schon vergeben: kein zweiter Zuhörer', (tester) async {
    await pump(tester, handoff: false);
    expect(await askHit(tester), isTrue);
    final c = containerOf(tester);
    await pumpUntil(tester, () => wake.done > 0);
    expect(c.read(voiceControllerProvider).active, isFalse);
    expect(logLines.where((l) => l.contains('voice-cancelled')), hasLength(1));
  });

  testWidgets('Bildschirm weg während des Zuhörens: Dienst hört wieder', (
    tester,
  ) async {
    await pump(tester);
    expect(await askHit(tester), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(wake.done, 1);
    expect(wake.handler, isNull);
  });

  group('WakeChatPolicy', () {
    test('nur sichtbar, oben und entsperrt', () {
      bool a(bool r, bool c, bool l) =>
          WakeChatPolicy.accepts(resumed: r, routeCurrent: c, locked: l);
      expect(a(true, true, false), isTrue);
      expect(a(false, true, false), isFalse);
      expect(a(true, false, false), isFalse);
      expect(a(true, true, true), isFalse);
    });
  });
}
