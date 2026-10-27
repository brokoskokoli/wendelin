// WP163 Teil B: Aktionen, die nur entsperrt wirken (Navigation u. a.):
// gesperrt nicht ausgeführt, gemerkt, nach dem Entsperren genau einmal.
@Timeout(Duration(seconds: 60))
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/ui/overlay/unlock_window.dart';
import 'package:wendelin/voice/locked_agent_run.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../overlay/assistant_overlay_test.dart'
    show FakeAssistantPlatform, overlaySample, pumpOverlay;
import '../support/test_env.dart';
import '../ui/helpers.dart' show pumpUntil;
import 'voice_controller_test.dart' show fakeVoice;

const _navigate = ToolCallBlock(
  id: '1',
  name: 'maps__navigate',
  argumentsJson: '{"destination":"Bahnhof"}',
);

TestEnv _env(FakeLlmProvider llm, {ToolPrefs? prefs}) => TestEnv(
  providerConfig: scripted(llm),
  startup: StartupSettings(
    enabledIntegrations: const {'flashlight', 'maps'},
    toolPrefs:
        prefs ??
        const ToolPrefs(
          levels: {'maps__navigate': 'a', 'maps__search_place': 'a'},
        ),
  ),
);

Future<void> _settle(WidgetTester tester, ProviderContainer c) async {
  // The run (session, tools, model) needs real time next to the fake clock:
  // `pumpUntil` waits in real steps and pumps in between. Never await
  // `whenIdle` without pumping (the fake clock then stands still).
  var idle = false;
  unawaited(
    c.read(voiceControllerProvider.notifier).whenIdle.then((_) => idle = true),
  );
  await pumpUntil(
    tester,
    () {
      final v = c.read(voiceControllerProvider);
      return idle && !v.active && !v.preparing;
    },
    timeout: const Duration(seconds: 30),
    reason: 'Pipeline wurde nicht frei',
  );
}

void main() {
  late FakeLlmProvider llm;
  late FakeAssistantPlatform platform;
  late FakeTextToSpeech tts;

  setUp(() {
    llm = FakeLlmProvider([
      ScriptedTurn.toolCalls([_navigate]),
      ScriptedTurn.text('Los geht es.'),
    ]);
    tts = FakeTextToSpeech();
  });

  Future<ProviderContainer> run(
    WidgetTester tester,
    TestEnv env, {
    String said = 'Navigiere zum Bahnhof',
    bool unlockSucceeds = false,
    Completer<bool>? gate,
  }) async {
    platform = FakeAssistantPlatform()
      ..locked = true
      ..unlockSucceeds = unlockSucceeds
      ..unlockGate = gate;
    final c = await pumpOverlay(
      tester,
      env,
      platform,
      voice: fakeVoice(
        script: [Transcript(text: said, language: 'de')],
        tts: tts,
      ),
    );
    c.read(agentControllerProvider.notifier).seed(overlaySample());
    await _settle(tester, c);
    return c;
  }

  testWidgets('gesperrt: nicht ausgeführt, fester Satz, Entsperr-Abfrage, '
      'Abbruch verwirft den Aufruf', (tester) async {
    final env = _env(llm);
    final c = await run(tester, env);
    expect(env.mapsLauncher.launched, isEmpty);
    expect(tts.spoken.join(' '), 'Zum Navigieren bitte entsperren.');
    expect(platform.unlockRequests, 1);
    expect(llm.requests, hasLength(1), reason: 'Lauf endet, kein 2. Zug');
    // Abgebrochen: verworfen, nie ausgeführt.
    expect(c.read(lockedPendingProvider), isNull);
    expect(c.read(lockedArmedCallProvider), isNull);
    expect(env.mapsLauncher.launched, isEmpty);
    // Die Werkzeugargumente stehen nicht im gesperrten Austausch.
    expect(c.read(lockedExchangeProvider)?.answer, isNot(contains('Bahnhof')));
  });

  testWidgets('gemerkt wird Werkzeug plus Argumente, nicht der Wortlaut', (
    tester,
  ) async {
    final c = await run(tester, _env(llm), gate: Completer<bool>());
    final p = c.read(lockedPendingProvider)!;
    expect(p.call?.name, 'maps__navigate');
    expect(p.call?.argumentsJson, contains('Bahnhof'));
    platform.unlockGate!.complete(false);
    await tester.pump();
  });

  testWidgets('nach dem Entsperren genau einmal, ohne weiteren Modelllauf', (
    tester,
  ) async {
    final env = _env(llm);
    final c = await run(tester, env, unlockSucceeds: true);
    expect(env.mapsLauncher.launched, hasLength(1));
    expect(llm.requests, hasLength(1), reason: 'kein Modelllauf danach');
    expect(c.read(lockedPendingProvider), isNull);
    expect(c.read(lockedArmedCallProvider), isNull);
    expect(tts.spoken.last, 'Navigation gestartet');
    // Ein weiterer Lauf mit demselben Text führt nichts erneut aus.
    expect(
      c.read(lockedArmedCallProvider.notifier).takeFor('Navigiere zum Bahnhof'),
      isNull,
    );
  });

  testWidgets('Ablauf (60 s) vor dem Entsperren: nie ausgeführt', (
    tester,
  ) async {
    final env = _env(llm);
    final c = await run(tester, env, gate: Completer<bool>());
    env.clock.advance(lockedPendingCallMaxAge + const Duration(seconds: 1));
    platform.unlockGate!.complete(true);
    await _settle(tester, c);
    expect(env.mapsLauncher.launched, isEmpty);
    expect(c.read(lockedPendingProvider), isNull);
  });

  testWidgets('Schließen des Overlays verwirft den Aufruf', (tester) async {
    final env = _env(llm);
    // The unlock failed at once (window over): a call is remembered and armed.
    final c = await run(tester, env);
    env.clock.advance(unlockGrace);
    c.read(lockedPendingProvider.notifier).keepCall('Navigiere', _navigate);
    c
        .read(lockedArmedCallProvider.notifier)
        .arm(c.read(lockedPendingProvider)!);
    expect(c.read(lockedArmedCallProvider), isNotNull);
    await platform.closeHandler!();
    await tester.pump();
    expect(c.read(lockedPendingProvider), isNull);
    expect(c.read(lockedArmedCallProvider), isNull);
    expect(env.mapsLauncher.launched, isEmpty);
  });

  testWidgets('Stufe nicht erlaubt: wie bisher „Entsperren nötig“, Wortlaut '
      'gemerkt', (tester) async {
    final env = _env(
      llm,
      // Navigation bleibt C; ein anderes Tool auf A hält den Modelllauf offen.
      prefs: const ToolPrefs(levels: {'maps__search_place': 'a'}),
    );
    final c = await run(tester, env, gate: Completer<bool>());
    expect(env.mapsLauncher.launched, isEmpty);
    expect(tts.spoken.join(' '), isNot(contains('Navigieren')));
    final p = c.read(lockedPendingProvider)!;
    expect(p.call, isNull, reason: 'Wortlaut, kein Aufruf');
    expect(p.text, 'Navigiere zum Bahnhof');
    platform.unlockGate!.complete(false);
    await tester.pump();
  });

  testWidgets('erst erledigt, dann zurückgestellt: nur der zurückgestellte '
      'Aufruf läuft nach dem Entsperren', (tester) async {
    // One round: the torch runs locked, the navigation waits. (A round of
    // the torch alone would end with its fixed sentence, WP122.)
    llm = FakeLlmProvider([
      ScriptedTurn.toolCalls([
        const ToolCallBlock(
          id: '0',
          name: 'flashlight__on',
          argumentsJson: '{}',
        ),
        _navigate,
      ]),
      ScriptedTurn.text('x'),
    ]);
    final env = _env(llm);
    await run(tester, env, unlockSucceeds: true);
    expect(
      env.torch.methodCalls.where((m) => m == 'set'),
      hasLength(1),
      reason: 'Taschenlampe nur gesperrt, nicht nach dem Entsperren',
    );
    expect(env.mapsLauncher.launched, hasLength(1));
    expect(llm.requests, hasLength(1), reason: 'kein Modelllauf nach dem Entsperren');
  });
}
