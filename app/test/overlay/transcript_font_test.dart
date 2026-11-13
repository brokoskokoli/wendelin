import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/overlay/overlay_sheet.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart' show PrivacyLevel;

import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'assistant_overlay_test.dart' show FakeAssistantPlatform, pumpOverlay;

// WP196: the user's request gets smaller with its length.

Widget _sheet(String request) => OverlaySheet(
  providerName: 'Claude',
  privacy: PrivacyLevel.standard,
  exchange: OverlayExchange(request: request),
  mic: MicState.idle,
  levels: const [],
  onMic: () {},
  onClose: () {},
  onKeyboard: () {},
  onUndo: (_) {},
);

Widget _app(Widget child, {double scale = 1}) => themed(
  Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: Scaffold(body: child),
    ),
  ),
);

final _quoted = find.textContaining('„');

double _size(WidgetTester tester) =>
    tester.widget<Text>(_quoted).style!.fontSize!;

void main() {
  group('Transkript im Overlay', () {
    for (final (n, size) in [(150, 26.0), (250, 18.2), (600, 16.0)]) {
      testWidgets('$n Zeichen: $size', (tester) async {
        setView(tester, screenSize);
        await tester.pumpWidget(_app(_sheet('x' * n)));
        expect(_size(tester), closeTo(size, 1e-9));
      });
    }

    testWidgets('Grenzen: 199 groß, 200 und 499 mittel, 500 klein', (
      tester,
    ) async {
      setView(tester, screenSize);
      for (final (n, size) in [
        (199, 26.0),
        (200, 18.2),
        (499, 18.2),
        (500, 16.0),
      ]) {
        await tester.pumpWidget(_app(_sheet('x' * n)));
        expect(_size(tester), closeTo(size, 1e-9), reason: '$n');
      }
    });

    testWidgets('Zeilenhöhe wächst in Stufen', (tester) async {
      setView(tester, screenSize);
      final heights = <double>[];
      for (final n in [150, 250, 600]) {
        await tester.pumpWidget(_app(_sheet('x' * n)));
        heights.add(tester.widget<Text>(_quoted).style!.height!);
      }
      expect(heights, [1.2, 1.25, 1.3]);
    });

    testWidgets('Hysterese: 250 → 190 bleibt klein, 170 wieder groß', (
      tester,
    ) async {
      setView(tester, screenSize);
      await tester.pumpWidget(_app(_sheet('x' * 250)));
      expect(_size(tester), closeTo(18.2, 1e-9));
      await tester.pumpWidget(_app(_sheet('x' * 190)));
      expect(_size(tester), closeTo(18.2, 1e-9));
      await tester.pumpWidget(_app(_sheet('x' * 170)));
      expect(_size(tester), 26);
    });

    testWidgets('Hysterese: Stufe 2 fällt erst unter 450', (tester) async {
      setView(tester, screenSize);
      await tester.pumpWidget(_app(_sheet('x' * 600)));
      await tester.pumpWidget(_app(_sheet('x' * 460)));
      expect(_size(tester), 16);
      await tester.pumpWidget(_app(_sheet('x' * 440)));
      expect(_size(tester), closeTo(18.2, 1e-9));
    });

    testWidgets('anderer Text startet frisch', (tester) async {
      setView(tester, screenSize);
      await tester.pumpWidget(_app(_sheet('a' * 250)));
      await tester.pumpWidget(_app(_sheet('b' * 190)));
      expect(_size(tester), 26);
    });

    testWidgets('TextScaler 1.5 wirkt weiter, Größe bleibt relativ', (
      tester,
    ) async {
      setView(tester, screenSize);
      await tester.pumpWidget(_app(_sheet('x' * 250), scale: 1.5));
      expect(_size(tester), closeTo(18.2, 1e-9));
      final p = tester.renderObject<RenderParagraph>(
        find.descendant(of: _quoted, matching: find.byType(RichText)).first,
      );
      expect(p.textScaler, TextScaler.linear(1.5));
      expect(p.textScaler.scale(18.2), closeTo(27.3, 1e-9));
    });
  });

  group('Stufen', () {
    test('Untergrenze ist die Body-Größe', () {
      expect(WText.transcriptFor(5000).fontSize, WText.body.fontSize);
    });
  });

  testWidgets('UserBubble bleibt bei 600 Zeichen bei 16', (tester) async {
    setView(tester, screenSize);
    await tester.pumpWidget(_app(UserBubble('x' * 600)));
    final t = tester.widget<Text>(find.byType(Text));
    expect(t.style!.fontSize, 16);
  });

  testWidgets('Golden: Overlay mit langer Anfrage', tags: ['golden'], (
    tester,
  ) async {
    final env = TestEnv(
      providerConfig: scripted(FakeLlmProvider(const []), name: 'Claude Haiku'),
    );
    final c = await pumpOverlay(
      tester,
      env,
      FakeAssistantPlatform(),
      autoStart: false,
    );
    final request = List.filled(
      12,
      'Bitte plane mir die Woche mit Terminen und Aufgaben.',
    ).join(' ');
    c
        .read(agentControllerProvider.notifier)
        .seed(
          ConversationState(
            entries: [
              SessionStartEntry('s', testNow),
              UserEntry('u1', request),
            ],
          ),
        );
    await tester.pumpAndSettle();
    expect(_size(tester), 16);
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/overlay_langer_text.png'),
    );
  });
}
