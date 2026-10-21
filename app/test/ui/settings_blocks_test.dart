import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/settings_page.dart';

import 'helpers.dart';

Future<void> _pump(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(themed(Scaffold(body: Center(child: w))));
  await tester.pumpAndSettle();
}

void main() {
  group('Überschrift', () {
    testWidgets('SettingsSection und SectionCard-Titel: 18/600 in text', (
      tester,
    ) async {
      await _pump(
        tester,
        const Column(
          children: [
            SettingsSection(title: 'Abschnitt', children: [Text('x')]),
            SectionCard(title: 'Karte', children: [Text('y')]),
          ],
        ),
      );
      for (final t in ['Abschnitt', 'Karte']) {
        final style = tester.widget<Text>(find.text(t)).style!;
        expect(style.fontSize, 18);
        expect(style.fontWeight, FontWeight.w600);
        expect(style.color, WColors.text);
      }
    });
  });

  group('InfoBox', () {
    testWidgets('Fläche surfaceRaised, ⓘ, Text 14 sekundär', (tester) async {
      await _pump(tester, const InfoBox('Erläuterung'));
      final deco =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(InfoBox),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(deco.color, WColors.surfaceRaised);
      expect(deco.borderRadius, isNotNull);
      final style = tester.widget<Text>(find.text('Erläuterung')).style!;
      expect(style.fontSize, 14);
      expect(style.color, WColors.textSecondary);
      expect(
        find.descendant(of: find.byType(InfoBox), matching: find.byType(WIcon)),
        findsOneWidget,
      );
    });

    testWidgets('SettingsPage.intro erscheint als InfoBox', (tester) async {
      await tester.pumpWidget(
        themed(const SettingsPage(title: 'T', intro: 'Hinweis', children: [])),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(InfoBox),
          matching: find.text('Hinweis'),
        ),
        findsOneWidget,
      );
    });
  });

  group('LinkButton', () {
    testWidgets('Outlined, linksbündig, ≥ 44, ↗, löst aus', (tester) async {
      var taps = 0;
      await _pump(tester, LinkButton('Öffnen', onPressed: () => taps++));
      final button = find.byType(OutlinedButton);
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      expect(
        find.descendant(of: button, matching: find.byType(WIcon)),
        findsOneWidget,
      );
      expect(tester.getTopLeft(button).dx, lessThan(5));
      await tester.tap(button);
      expect(taps, 1);
    });

    testWidgets('external: false zeigt kein ↗', (tester) async {
      await _pump(tester, LinkButton('Hin', external: false, onPressed: () {}));
      expect(find.byType(WIcon), findsNothing);
    });
  });
}
