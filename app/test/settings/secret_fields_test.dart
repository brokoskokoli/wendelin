// B1 (WP32): every secret field is the shared SecretField – masked, offered
// to the password manager (autofill), no keyboard suggestions – inside an
// AutofillGroup. Bring! groups e-mail (username) and password.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/bring_screen.dart';
import 'package:wendelin/ui/settings/http_tool_editor_screen.dart';
import 'package:wendelin/ui/settings/provider_setup_screen.dart';
import 'package:wendelin/ui/settings/web_search_screen.dart';

import '../support/test_env.dart';
import 'lists_and_web_test.dart' show pumpPage;

/// The text field inside the widget with [key].
TextField fieldOf(WidgetTester tester, Key key) => tester.widget<TextField>(
  find.descendant(
    of: find.byKey(key),
    matching: find.byType(TextField),
    matchRoot: true,
  ),
);

/// Checks the secret field with [key]: shared building block, masked,
/// password autofill, no suggestions, inside an [AutofillGroup].
void expectSecret(WidgetTester tester, Key key) {
  expect(
    tester.widget(find.byKey(key)),
    isA<SecretField>(),
    reason: 'gemeinsamer Baustein',
  );
  final field = fieldOf(tester, key);
  expect(field.obscureText, isTrue);
  expect(field.autofillHints, [AutofillHints.password]);
  expect(field.enableSuggestions, isFalse);
  expect(field.autocorrect, isFalse);
  expect(field.enableIMEPersonalizedLearning, isFalse);
  expect(
    find.ancestor(of: find.byKey(key), matching: find.byType(AutofillGroup)),
    findsOneWidget,
  );
}

void main() {
  testWidgets('Provider: API-Key', (tester) async {
    await pumpPage(tester, TestEnv(), const ProviderSetupScreen());
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();
    expectSecret(tester, const ValueKey('apiKey'));
  });

  testWidgets('Websuche: API-Key', (tester) async {
    await pumpPage(tester, TestEnv(), const WebSearchScreen());
    await tester.tap(find.text('Brave Search'));
    await tester.pumpAndSettle();
    expectSecret(tester, const ValueKey('searchKey'));
  });

  testWidgets('Bring!: E-Mail und Passwort in einer Autofill-Gruppe', (
    tester,
  ) async {
    await pumpPage(tester, TestEnv(), const BringScreen());
    expectSecret(tester, const ValueKey('bringPassword'));
    final email = fieldOf(tester, const ValueKey('bringEmail'));
    expect(email.autofillHints, contains(AutofillHints.username));
    expect(email.obscureText, isFalse);
    final group = find.ancestor(
      of: find.byKey(const ValueKey('bringPassword')),
      matching: find.byType(AutofillGroup),
    );
    expect(
      find.descendant(
        of: group,
        matching: find.byKey(const ValueKey('bringEmail')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('HTTP-Tool: Bearer-Token und geheimer Header', (tester) async {
    await pumpPage(tester, TestEnv(), const HttpToolEditorScreen());
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Bearer-Token'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bearer-Token'));
    await tester.pumpAndSettle();
    expectSecret(tester, const ValueKey('secret'));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Geheime Header'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('+ Geheimer Header'));
    await tester.tap(find.text('+ Geheimer Header'));
    await tester.pumpAndSettle();
    expectSecret(tester, const ValueKey('secretHeaderValue0'));
  });
}
