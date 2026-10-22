// WP128: the offer „Mit X nochmal?“ in the chat sheet.

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/screens/confirmation_sheet.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../ui/helpers.dart';

void main() {
  testWidgets('Schaltfläche „Mit X nochmal?“ und Nein antworten', (
    tester,
  ) async {
    final answers = <bool>[];
    final question = RetryOfferQuestion(
      RetryOfferRequired(
        fromProfile: 'phala',
        toProfile: 'tinfoil',
        error: const ProviderTimeoutException('langsam'),
        respond: (_) {},
      ),
      fromName: 'Phala',
      toName: 'Tinfoil',
    );
    await pumpComponent(tester, [
      confirmationCardFor(AppLocalizationsDe(), question, answers.add),
    ]);
    expect(find.textContaining('Phala antwortet gerade nicht'), findsOneWidget);
    await tester.tap(find.text('Mit Tinfoil nochmal?').last);
    await tester.tap(find.text('Nein'));
    expect(answers, [true, false]);
  });
}
