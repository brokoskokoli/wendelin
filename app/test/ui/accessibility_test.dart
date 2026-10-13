import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/design/compositions.dart';
import 'package:wendelin/ui/design/gallery.dart';
import 'package:wendelin/ui/theme/app_theme.dart';

import 'helpers.dart';

Future<void> _expectGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  group('Bausteine erfüllen Tap-Target-, Label- und Kontrastregeln', () {
    for (final section in gallerySections.entries) {
      testWidgets(section.key, (tester) async {
        final handle = tester.ensureSemantics();
        await pumpComponent(tester, section.value);
        await _expectGuidelines(tester);
        handle.dispose();
      });
    }
  });

  group('Screens erfüllen Tap-Target-, Label- und Kontrastregeln', () {
    final screens = <String, Widget>{
      'hauptbildschirm': const MainScreenSample(),
      'bestaetigung': const ConfirmationSheetSample(),
      'integrationen': const IntegrationsSample(),
    };
    for (final s in screens.entries) {
      testWidgets(s.key, (tester) async {
        final handle = tester.ensureSemantics();
        await pumpScreen(tester, s.value);
        await _expectGuidelines(tester);
        handle.dispose();
      });
    }
  });

  testWidgets('Galerie lässt sich bauen und zeigt alle Abschnitte', (
    tester,
  ) async {
    setView(tester, const Size(390, 844));
    await tester.pumpWidget(themed(const DesignGallery()));
    await tester.pumpAndSettle();
    expect(find.text('Design-System'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Integrationen'), 500);
    await tester.ensureVisible(find.text('Integrationen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Integrationen'));
    await tester.pumpAndSettle();
    expect(find.byType(IntegrationsSample), findsOneWidget);
  });

  group('Gegenprobe: die Prüfungen schlagen an', () {
    testWidgets('zu kleines Tap-Target', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpComponent(tester, [
        Semantics(
          button: true,
          label: 'klein',
          child: GestureDetector(
            onTap: () {},
            child: const SizedBox(width: 30, height: 30),
          ),
        ),
      ]);
      final result = await androidTapTargetGuideline.evaluate(tester);
      expect(result.passed, isFalse);
      handle.dispose();
    });

    testWidgets('zu wenig Kontrast', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpComponent(tester, [
        Text('kaum lesbar', style: WText.caption.copyWith(color: WColors.line)),
      ]);
      final result = await textContrastGuideline.evaluate(tester);
      expect(result.passed, isFalse);
      handle.dispose();
    });
  });
}
