import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/platform/screen_protection.dart';
import 'package:wendelin/ui/settings/wake/wake_calibrate_screen.dart';
import 'package:wendelin/ui/settings/wake/wake_enroll_screen.dart';
import 'package:wendelin/ui/settings/wake/wake_test_screen.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;
import 'wake_word_screen_test.dart' hide main;

/// Microphone that never ends; counts the starts.
final class OpenAudio implements AudioInput {
  int starts = 0;
  bool _on = false;
  StreamController<Int16List>? _c;

  @override
  bool get isRunning => _on;

  @override
  Stream<Int16List> start() {
    starts++;
    _on = true;
    return (_c = StreamController<Int16List>()).stream;
  }

  @override
  Future<void> stop() async {
    _on = false;
    await _c?.close();
  }
}

void main() {
  Future<void> background(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
  }

  testWidgets('Kalibrieren: Screen verlassen während keepScreenOn startet '
      'das Mikrofon nie', (tester) async {
    final gate = Completer<void>();
    final calls = <bool>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(windowChannelName), (
      call,
    ) async {
      if (call.method == 'setKeepScreenOn') {
        final on = (call.arguments as Map)['on'] as bool;
        calls.add(on);
        if (on) await gate.future;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel(windowChannelName),
        null,
      ),
    );
    final audio = OpenAudio();
    final env = wakeEnv(audio: audio);
    final store = SecretWakeTemplateStore(env.secrets);
    await tester.runAsync(() => store.save(templates('a')));
    final t = (await tester.runAsync(() => store.load('a')))!;
    await pumpWake(tester, env, WakeCalibrateScreen(templates: t));
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, [true]);
    await tester.pumpWidget(const SizedBox()); // Screen verlassen
    gate.complete();
    await settle(tester);
    expect(audio.starts, 0);
    expect(calls, [true, false]);
  });

  testWidgets('Kalibrieren: Hintergrund gibt das Mikrofon frei', (
    tester,
  ) async {
    final audio = OpenAudio();
    final env = wakeEnv(
      audio: audio,
      extra: [screenProtectionProvider.overrideWithValue(_NoScreen())],
    );
    final store = SecretWakeTemplateStore(env.secrets);
    await tester.runAsync(() => store.save(templates('a')));
    final t = (await tester.runAsync(() => store.load('a')))!;
    await pumpWake(tester, env, WakeCalibrateScreen(templates: t));
    await until(tester, find.text('Abbrechen'));
    expect(audio.isRunning, isTrue);
    await background(tester);
    expect(audio.isRunning, isFalse);
  });

  testWidgets('Einlernen: Hintergrund gibt das Mikrofon frei', (tester) async {
    final audio = OpenAudio();
    final env = wakeEnv(audio: audio);
    await pumpWake(
      tester,
      env,
      const WakeEnrollScreen(speakerId: 'a', name: 'Anna'),
    );
    await until(tester, find.text('Abbrechen'));
    expect(audio.isRunning, isTrue);
    await background(tester);
    expect(audio.isRunning, isFalse);
  });

  testWidgets('Ausprobieren: Hintergrund gibt das Mikrofon frei', (
    tester,
  ) async {
    final audio = OpenAudio();
    final env = wakeEnv(audio: audio);
    await pumpWake(tester, env, WakeTestScreen(speakers: [templates('a')]));
    await pumpUntil(tester, () => audio.isRunning);
    expect(audio.isRunning, isTrue);
    await background(tester);
    expect(audio.isRunning, isFalse);
  });
}

final class _NoScreen extends ScreenProtection {
  const _NoScreen();
  @override
  Future<void> keepScreenOn({required bool on}) async {}
}
