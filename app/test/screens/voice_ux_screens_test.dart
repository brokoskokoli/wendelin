// WP31: Zuhör-Leiste, Senden-Knopf, „Neues Gespräch“ im Kopf, Mikrofon-
// Zustände im Hauptbildschirm.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/screens/main_parts.dart';
import 'package:wendelin/voice/voice_controller.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'main_screen_test.dart' show containerOf, pumpApp;

Widget _composer({
  MicState mic = MicState.idle,
  List<double> levels = const [],
  bool Function(String)? onSend,
}) => Composer(
  running: false,
  mic: mic,
  levels: levels,
  onMic: () {},
  onSend: onSend ?? (_) => true,
);

Future<void> _pumpComposer(WidgetTester tester, Widget composer) async {
  setView(tester, const Size(390, 300));
  await tester.pumpWidget(
    themed(
      RepaintBoundary(
        key: goldenKey,
        child: Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: composer),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<double> _amplitudes(WidgetTester tester) =>
    tester.widget<Waveform>(find.byType(Waveform)).amplitudes;

void main() {
  group('Zuhör-Leiste', () {
    testWidgets('nur beim Zuhören, folgt den Pegeln', tags: ['golden'], (
      tester,
    ) async {
      await _pumpComposer(tester, _composer());
      expect(find.byType(ListeningBar), findsNothing);

      await _pumpComposer(
        tester,
        _composer(mic: MicState.listening, levels: const [0.1, 0.9]),
      );
      expect(find.text('Ich höre zu …'), findsOneWidget);
      expect(_amplitudes(tester), [0, 0, 0, 0, 0.1, 0.9]);

      await _pumpComposer(
        tester,
        _composer(mic: MicState.listening, levels: const [0.3, 0.2, 0.7]),
      );
      expect(_amplitudes(tester), [0, 0, 0, 0.3, 0.2, 0.7]);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/composer_listening.png'),
      );
    });

    testWidgets('Vorbereiten zeigt „Moment …“', (tester) async {
      await _pumpComposer(tester, _composer(mic: MicState.preparing));
      expect(find.text('Moment …'), findsOneWidget);
      expect(find.byType(ListeningBar), findsNothing);
      expect(find.byTooltip('Moment …'), findsOneWidget);
    });
  });

  group('Senden-Knopf', () {
    testWidgets('erscheint nur mit Text und sendet', tags: ['golden'], (
      tester,
    ) async {
      final sent = <String>[];
      await _pumpComposer(
        tester,
        _composer(
          onSend: (t) {
            sent.add(t);
            return true;
          },
        ),
      );
      expect(find.byType(SendButton), findsNothing);
      expect(find.byType(MicButton), findsOneWidget);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(find.byType(SendButton), findsNothing);

      await tester.enterText(find.byType(TextField), 'Hallo Wendelin');
      await tester.pump();
      expect(find.byType(SendButton), findsOneWidget);
      expect(find.byType(MicButton), findsNothing);
      expect(find.byTooltip('Senden'), findsOneWidget);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/composer_send.png'),
      );

      await tester.tap(find.byType(SendButton));
      await tester.pump();
      expect(sent, ['Hallo Wendelin']);
      expect(find.byType(SendButton), findsNothing);
      expect(find.byType(MicButton), findsOneWidget);
    });

    testWidgets('Enter sendet weiter', (tester) async {
      final sent = <String>[];
      await _pumpComposer(
        tester,
        _composer(
          onSend: (t) {
            sent.add(t);
            return true;
          },
        ),
      );
      await tester.enterText(find.byType(TextField), 'per Enter');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(sent, ['per Enter']);
    });
  });

  group('Hauptbildschirm', () {
    testWidgets('„Neues Gespräch“ im Kopf: nur mit Verlauf, leert ihn', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, TestEnv(demo: true));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byTooltip('Neues Gespräch'), findsNothing);

      final c = containerOf(tester);
      c
          .read(agentControllerProvider.notifier)
          .seed(
            ConversationState(
              entries: [
                SessionStartEntry('s', testNow),
                const UserEntry('u', 'Hallo'),
                const AssistantTextEntry('a', 'Guten Morgen.'),
              ],
            ),
          );
      await tester.pump();
      final button = find.byTooltip('Neues Gespräch');
      expect(button, findsOneWidget);
      expect(find.text('Guten Morgen.'), findsOneWidget);
      final size = tester.getSize(button);
      expect(size.shortestSide, greaterThanOrEqualTo(44));
      expect(
        tester
            .getSemantics(
              find.ancestor(of: button, matching: find.byType(IconButton)),
            )
            .getSemanticsData()
            .tooltip,
        'Neues Gespräch',
      );

      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('Guten Morgen.'), findsNothing);
      expect(
        c.read(agentControllerProvider).entries.whereType<UserEntry>(),
        isEmpty,
      );
      expect(find.byTooltip('Neues Gespräch'), findsNothing);
      handle.dispose();
    });

    testWidgets('Mikrofon: Vorbereiten, Ring bei Ja/Nein, Sprechen', (
      tester,
    ) async {
      await pumpApp(tester, TestEnv(demo: true));
      await tester.pump(const Duration(milliseconds: 50));
      final c = containerOf(tester);
      MicState mic() => tester.widget<MicButton>(find.byType(MicButton)).state;
      final voice = c.read(voiceControllerProvider.notifier);

      voice.seed(const VoiceUiState(preparing: true));
      await tester.pump();
      expect(mic(), MicState.preparing);
      expect(find.text('Moment …'), findsOneWidget);

      voice.seed(const VoiceUiState(awaitingAnswer: true));
      await tester.pump();
      expect(mic(), MicState.listening);
      expect(find.byType(ListeningBar), findsOneWidget);
    });
  });
}
