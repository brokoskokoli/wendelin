// WP201: the confirmation card names why it asks after foreign content.

import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/screens/confirmation_sheet.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../ui/helpers.dart';

void main() {
  final l = AppLocalizationsDe();

  ToolQuestion question({required bool foreign}) => ToolQuestion(
    ConfirmationRequired(
      call: const ToolCallBlock(
        id: 'c1',
        name: 'mcp_x__set',
        argumentsJson: '{}',
      ),
      description: 'Lampe an',
      respond: (_) {},
      askedBecauseForeign: foreign,
    ),
    request: 'Mach das Licht an',
  );

  testWidgets('Grund sichtbar, wenn wegen fremder Inhalte gefragt wird', (
    tester,
  ) async {
    await pumpComponent(tester, [
      confirmationCardFor(l, question(foreign: true), (_) {}),
    ]);
    expect(find.text(l.confirmCardForeignReason), findsOneWidget);
  });

  testWidgets('ohne Grund kein Grundtext', (tester) async {
    await pumpComponent(tester, [
      confirmationCardFor(l, question(foreign: false), (_) {}),
    ]);
    expect(find.text(l.confirmCardForeignReason), findsNothing);
    expect(find.byKey(const ValueKey('confirmationReason')), findsNothing);
  });
}
