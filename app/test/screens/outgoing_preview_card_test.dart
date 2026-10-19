// WP85: preview popup before an SMS or call. Only a tap on „Absenden“ /
// „Anrufen“ answers yes; the text shown is the text that is sent.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/sms_drafts.dart';
import 'package:wendelin/ui/screens/confirmation_sheet.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../ui/helpers.dart';

ToolQuestion _question(
  String tool,
  String args,
  String description,
  List<bool> answers,
) => ToolQuestion(
  ConfirmationRequired(
    call: ToolCallBlock(id: 'c1', name: tool, argumentsJson: args),
    description: description,
    respond: answers.add,
  ),
  request: 'Schreib Anna',
);

ToolQuestion _sms(List<bool> answers) => _question(
  'sms__compose',
  '{"to":"+49 170 1234567","text":"Ich komme später"}',
  'SMS an Anna Meier (+491701234567)\nIch komme später',
  answers,
);

ToolQuestion _call(List<bool> answers) => _question(
  'phone__call',
  '{"to":"0171 111"}',
  'Anrufen: Ben Schmidt (0171111)',
  answers,
);

void main() {
  late ProviderContainer container;
  late List<bool?> results;

  Future<void> pump(WidgetTester tester, ToolQuestion q) async {
    setView(tester, const Size(390, 844));
    container = ProviderContainer();
    addTearDown(container.dispose);
    results = [];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: themed(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async => results.add(
                  await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ConfirmationSheet(
                      question: q,
                      providerName: 'Claude',
                      privacy: PrivacyLevel.standard,
                    ),
                  ),
                ),
                child: const Text('öffnen'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
  }

  testWidgets('SMS: Name, Nummer, Text; nichts ohne Tipp', (tester) async {
    await pump(tester, _sms([]));
    expect(find.text('Anna Meier'), findsOneWidget);
    expect(find.textContaining('+491701234567'), findsWidgets);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('smsText')))
          .controller!
          .text,
      'Ich komme später',
    );
    expect(find.widgetWithText(FilledButton, 'Absenden'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('SMS: Tipp auf „Absenden“ antwortet ja', (tester) async {
    await pump(tester, _sms([]));
    await tester.tap(find.widgetWithText(FilledButton, 'Absenden'));
    await tester.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets('SMS: „Abbrechen“ antwortet nein und verwirft die Änderung', (
    tester,
  ) async {
    await pump(tester, _sms([]));
    await tester.enterText(find.byKey(const ValueKey('smsText')), 'Anders');
    final edits = container.read(smsDraftEditsProvider);
    expect(edits.isEdited('+491701234567', 'Ich komme später'), isTrue);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(results, [false]);
    await tester.pumpWidget(const SizedBox());
    expect(edits.isEdited('+491701234567', 'Ich komme später'), isFalse);
  });

  testWidgets('SMS: geänderter Text wird als Änderung vermerkt', (
    tester,
  ) async {
    await pump(tester, _sms([]));
    await tester.enterText(find.byKey(const ValueKey('smsText')), 'Neu');
    final edits = container.read(smsDraftEditsProvider);
    expect(edits.isEdited('+491701234567', 'Ich komme später'), isTrue);
    await tester.tap(find.widgetWithText(FilledButton, 'Absenden'));
    await tester.pumpAndSettle();
    expect(results, [true]);
    // Approved: the edit stays for the tool, which takes it.
    await tester.pumpWidget(const SizedBox());
    expect(edits.take('+491701234567', 'Ich komme später'), 'Neu');
  });

  testWidgets('SMS: leerer Text sperrt „Absenden“', (tester) async {
    await pump(tester, _sms([]));
    await tester.enterText(find.byKey(const ValueKey('smsText')), '   ');
    await tester.pump();
    final yes = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Absenden'),
    );
    expect(yes.onPressed, isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Absenden'));
    await tester.pumpAndSettle();
    expect(results, isEmpty);
  });

  testWidgets('Anruf: Name und Nummer, kein Textfeld, Tipp auf „Anrufen“', (
    tester,
  ) async {
    await pump(tester, _call([]));
    expect(find.text('Ben Schmidt'), findsOneWidget);
    expect(find.textContaining('0171111'), findsWidgets);
    expect(find.byKey(const ValueKey('smsText')), findsNothing);
    expect(results, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Anrufen'));
    await tester.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets('Anruf: „Abbrechen“ antwortet nein', (tester) async {
    await pump(tester, _call([]));
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });
}
