import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../screens/main_screen_test.dart' show pumpApp;
import '../support/test_env.dart';
import '../voice/voice_controller_test.dart' show utterance;
import 'helpers.dart';

const _hold = Duration(milliseconds: 450);

/// 1.2 s lead-in (the hold arrives while the microphone already runs, as at
/// the device after 450 ms), 300 ms speech, 3 s pause, 300 ms speech.
List<Int16List> _withPause() =>
    AudioFrames.pattern('${'.' * 40}${'S' * 10}${'.' * 100}${'S' * 10}');

/// Gesture of the microphone button (WP192).
void main() {
  test('Haltegrenze der Geste = der des Controllers', () {
    expect(MicGesture.holdThreshold, kHoldThreshold);
    expect(kHoldThreshold, _hold);
  });

  group('MicButton Geste', () {
    final log = <String>[];
    Future<void> pumpButton(
      WidgetTester tester, {
      MicState state = MicState.idle,
      bool gesture = true,
      String? semanticLabel,
      bool keepLog = false,
    }) async {
      if (!keepLog) log.clear();
      await tester.pumpWidget(
        themed(
          Scaffold(
            body: Center(
              child: MicButton(
                state: state,
                semanticLabel: semanticLabel,
                onPressed: () => log.add('tap'),
                gesture: gesture
                    ? MicGesture(
                        onDown: () => log.add('down'),
                        onHold: () => log.add('hold'),
                        onUp: (h) => log.add('up:$h'),
                      )
                    : null,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Druck > Grenze, Wegrutschen, Loslassen: hold, kein Ende '
        'beim Wegrutschen, up:true; Haltezustand sichtbar', (tester) async {
      await pumpButton(tester);
      final g = await tester.startGesture(
        tester.getCenter(find.byType(MicButton)),
      );
      expect(log, ['down']);
      await tester.pump(_hold - const Duration(milliseconds: 1));
      expect(log, ['down']);
      await tester.pump(const Duration(milliseconds: 1));
      expect(log, ['down', 'hold']);
      expect(find.text('Loslassen zum Senden'), findsOneWidget);
      await g.moveBy(const Offset(0, -300));
      await g.moveBy(const Offset(200, 0));
      await tester.pump(const Duration(seconds: 3));
      expect(log, ['down', 'hold']);
      await g.up();
      await tester.pump();
      expect(log, ['down', 'hold', 'up:true']);
      expect(find.text('Loslassen zum Senden'), findsNothing);
    });

    testWidgets('Pointer-Cancel zählt wie Loslassen', (tester) async {
      await pumpButton(tester);
      final g = await tester.startGesture(
        tester.getCenter(find.byType(MicButton)),
      );
      await tester.pump(_hold);
      await g.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(log, ['down', 'hold', 'up:true']);
    });

    testWidgets('kurzer Tipp: down, up:false, kein hold, kein onPressed', (
      tester,
    ) async {
      await pumpButton(tester);
      await tester.tap(find.byType(MicButton));
      await tester.pump(const Duration(seconds: 1));
      expect(log, ['down', 'up:false']);
    });

    testWidgets('Semantics-Tipp ruft onPressed genau einmal', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpButton(tester);
      tester.semantics.tap(find.semantics.byLabel('Sprechen'));
      await tester.pump();
      expect(log, ['tap']);
      handle.dispose();
    });

    testWidgets('disabled: keine Geste', (tester) async {
      await pumpButton(tester, state: MicState.disabled);
      final g = await tester.startGesture(
        tester.getCenter(find.byType(MicButton)),
      );
      await tester.pump(_hold * 2);
      await g.up();
      expect(log, isEmpty);
    });

    testWidgets('Entfernen während eines Tipps: Timer sauber, kein up '
        '(nichts wird abgebrochen)', (tester) async {
      await pumpButton(tester);
      await tester.startGesture(tester.getCenter(find.byType(MicButton)));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(_hold * 2);
      expect(log, ['down']);
    });

    testWidgets('Entfernen während des Haltens: gehaltene Aufnahme wird '
        'freigegeben', (tester) async {
      await pumpButton(tester);
      await tester.startGesture(tester.getCenter(find.byType(MicButton)));
      await tester.pump(_hold);
      await tester.pumpWidget(const SizedBox());
      expect(log, ['down', 'hold', 'up:true']);
    });

    testWidgets('disabled während des Haltens: up:true (Aufnahme wird '
        'freigegeben)', (tester) async {
      await pumpButton(tester);
      await tester.startGesture(tester.getCenter(find.byType(MicButton)));
      await tester.pump(_hold);
      await pumpButton(tester, state: MicState.disabled, keepLog: true);
      expect(log, ['down', 'hold', 'up:true']);
      expect(find.text('Loslassen zum Senden'), findsNothing);
    });

    testWidgets('disabled während eines Tipps: up:false', (tester) async {
      await pumpButton(tester);
      await tester.startGesture(tester.getCenter(find.byType(MicButton)));
      await tester.pump(const Duration(milliseconds: 100));
      await pumpButton(tester, state: MicState.disabled, keepLog: true);
      expect(log, ['down', 'up:false']);
    });

    testWidgets('Halten: kein Tooltip springt auf, Pille bleibt allein', (
      tester,
    ) async {
      await pumpButton(tester, semanticLabel: 'Zuhören abbrechen');
      final g = await tester.startGesture(
        tester.getCenter(find.byType(MicButton)),
      );
      await tester.pump(const Duration(milliseconds: 1800));
      expect(find.byTooltip('Loslassen zum Senden'), findsOneWidget);
      // Declared, but not shown by the hold (no long-press trigger).
      expect(find.text('Zuhören abbrechen'), findsNothing);
      expect(find.text('Loslassen zum Senden'), findsOneWidget);
      await g.up();
    });

    testWidgets('Halten: Halte-Label schlägt das semanticLabel', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpButton(tester, semanticLabel: 'Zuhören abbrechen');
      expect(find.semantics.byLabel('Zuhören abbrechen'), findsOneWidget);
      final g = await tester.startGesture(
        tester.getCenter(find.byType(MicButton)),
      );
      await tester.pump(_hold);
      expect(find.semantics.byLabel('Loslassen zum Senden'), findsOneWidget);
      expect(find.semantics.byLabel('Zuhören abbrechen'), findsNothing);
      await g.up();
      await tester.pump();
      expect(find.semantics.byLabel('Zuhören abbrechen'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('ohne gesture: Tipp über onPressed wie bisher', (tester) async {
      await pumpButton(tester, gesture: false);
      await tester.tap(find.byType(MicButton));
      expect(log, ['tap']);
    });
  });

  group('Hauptbildschirm mit echtem Controller', () {
    testWidgets('Halten, Wegschieben, 3 s Pause, Loslassen: genau eine '
        'Äußerung mit ganzem Audio', (tester) async {
      final audio = FakeAudioInput(
        frames: _withPause(),
        frameInterval: const Duration(milliseconds: 10),
      );
      final stt = FakeSpeechToText(const [Transcript(text: 'Satz')]);
      final env = TestEnv(
        providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('Ok')])),
        extraOverrides: [
          voiceReadyProvider.overrideWithValue(true),
          activeVoiceProvider.overrideWith(
            (ref) async => VoiceComponents(
              audio: audio,
              vad: FakeVoiceActivityDetector(),
              stt: stt,
              textToSpeech: (_) async => FakeTextToSpeech(),
              config: const VoicePipelineConfig(),
            ),
          ),
        ],
      );
      await pumpApp(tester, env);
      await tester.pump();
      final g = await tester.startGesture(
        tester.getCenter(find.byType(MicButton)),
      );
      await tester.pump(_hold);
      await g.moveBy(const Offset(0, -400));
      await pumpUntil(tester, () => audio.deliveredFrames >= 160);
      await tester.pump(const Duration(milliseconds: 100));
      expect(stt.calls, isEmpty, reason: 'kein Stille-Ende beim Halten');
      expect(
        tester.widget<MicButton>(find.byType(MicButton)).state,
        MicState.listening,
      );
      await g.up();
      await pumpUntil(tester, () => stt.calls.isNotEmpty);
      expect(stt.calls, hasLength(1));
      expect(stt.calls.single.samples, greaterThanOrEqualTo(120 * 480));
      expect(audio.startCount, 1);
    });

    testWidgets('kurzer Tipp wie bisher: normales Endpointing', (tester) async {
      final audio = FakeAudioInput(
        frames: utterance(),
        frameInterval: const Duration(milliseconds: 1),
      );
      final stt = FakeSpeechToText(const [Transcript(text: 'Satz')]);
      final env = TestEnv(
        providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('Ok')])),
        extraOverrides: [
          voiceReadyProvider.overrideWithValue(true),
          activeVoiceProvider.overrideWith(
            (ref) async => VoiceComponents(
              audio: audio,
              vad: FakeVoiceActivityDetector(),
              stt: stt,
              textToSpeech: (_) async => FakeTextToSpeech(),
              config: const VoicePipelineConfig(),
            ),
          ),
        ],
      );
      await pumpApp(tester, env);
      await tester.tap(find.byType(MicButton));
      await pumpUntil(tester, () => stt.calls.isNotEmpty);
      expect(stt.calls, hasLength(1));
    });
  });
}
