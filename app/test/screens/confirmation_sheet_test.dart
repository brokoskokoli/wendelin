// Regression (Review WP16): ein langer Diff von obsidian__replace_section
// darf die Bestätigungskarte nicht sprengen – „Ja“ bleibt erreichbar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/ui/screens/confirmation_sheet.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../ui/helpers.dart';

void main() {
  String longDiff(int lines) => [
    'Abschnitt „Status“ in „Projekte/Wendelin.md“ ersetzen:',
    for (var i = 0; i < lines; i++)
      '${i.isEven ? '-' : '+'} Zeile $i ${'sehr langer Text ' * 12}',
  ].join('\n');

  test('clampConfirmationDetail kürzt Zeilen und Länge', () {
    expect(clampConfirmationDetail('kurz\nzwei'), 'kurz\nzwei');
    final out = clampConfirmationDetail(longDiff(60)).split('\n');
    expect(out, hasLength(maxDetailLines));
    expect(out.last, '… 52 weitere Zeilen');
    expect(out.every((l) => l.length <= maxDetailLineChars), isTrue);
    expect(out[1], endsWith('…'));
  });

  testWidgets(
    'langer Diff auf 390×844: kein Overflow, „Ja, ausführen“ sichtbar',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      bool? result;
      await tester.pumpWidget(
        themed(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ConfirmationSheet(
                      question: ToolQuestion(
                        ConfirmationRequired(
                          call: ToolCallBlock(
                            id: 'c1',
                            name: 'obsidian__replace_section',
                            argumentsJson: '{}',
                          ),
                          description: longDiff(80),
                          respond: (_) {},
                        ),
                        request: 'Ersetz den Status in Wendelin',
                      ),
                      providerName: 'Claude',
                      privacy: PrivacyLevel.standard,
                    ),
                  );
                },
                child: const Text('öffnen'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('öffnen'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final yes = find.widgetWithText(FilledButton, 'Ja, ausführen');
      expect(yes, findsOneWidget);
      final rect = tester.getRect(yes);
      // Ganz sichtbar: innerhalb des scrollbaren Bereichs, nicht abgeschnitten.
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(rect.bottom, lessThanOrEqualTo(844));
      await tester.tap(yes);
      await tester.pumpAndSettle();
      expect(result, isTrue);
    },
  );
}
