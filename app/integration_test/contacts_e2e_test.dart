// Gerätetest (WP85): Kontakte, SMS und Anruf mit Vorschau auf dem Emulator.
// Echte Ports/Kanäle, Skript-Provider statt Modell. Kontakte (Anna Meier 5554,
// Ben Schmidt 5556, Ben Weber 5558) und der Berechtigungsdialog werden vom
// Host (adb) bedient; Marken `E2E-MARK` im Log erlauben den Abgleich mit
// content://sms/sent.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/platform/channel_contacts_port.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'support/e2e.dart';

ToolCallBlock _call(String id, String name, String json) =>
    ToolCallBlock(id: id, name: name, argumentsJson: json);

void mark(String m) =>
    // ignore: avoid_print
    print('E2E-MARK ${DateTime.now().millisecondsSinceEpoch} $m');

Future<void> sendMsg(WidgetTester tester, String text) async {
  await waitIdle(tester);
  final f = find.byWidgetPredicate(
    (w) => w is TextField && w.key != const ValueKey('smsText'),
  );
  await tester.enterText(f, text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Kontakte, SMS-Vorschau, Anruf', (tester) async {
    final port = const ChannelContactsPort();
    mark('permission-request-start has=${await port.hasPermission()}');
    final granted = await port.requestPermission();
    mark(
      'permission-request-done granted=$granted sms=${await port.canSendSms()}',
    );
    expect(granted, isTrue);

    final llm = FakeLlmProvider([
      // 1 find Ben (mehrdeutig)
      ScriptedTurn.toolCalls([
        _call('c1', 'contacts__find', '{"query":"Ben"}'),
      ]),
      ScriptedTurn.text('Welcher Ben: Schmidt oder Weber?'),
      // 2 find Anna
      ScriptedTurn.toolCalls([
        _call('c2', 'contacts__find', '{"query":"Anna"}'),
      ]),
      ScriptedTurn.text('Annas Nummer ist 5554.'),
      // 3 SMS, Absenden mit geändertem Text
      ScriptedTurn.toolCalls([
        _call('c3', 'sms__compose', '{"to":"5554","text":"Ich komme spaeter"}'),
      ]),
      ScriptedTurn.text('SMS erledigt.'),
      // 4 SMS, Abbrechen
      ScriptedTurn.toolCalls([
        _call('c4', 'sms__compose', '{"to":"5554","text":"NICHT SENDEN"}'),
      ]),
      ScriptedTurn.text('Abgebrochen.'),
      // 5 Anruf
      ScriptedTurn.toolCalls([_call('c5', 'phone__call', '{"to":"5556"}')]),
      ScriptedTurn.text('Anruf erledigt.'),
    ]);
    final app = E2eApp(
      startup: const StartupSettings(enabledIntegrations: {'contacts'}),
      extraOverrides: [
        llmProviderFactoryProvider.overrideWithValue((p, _) => llm),
      ],
    );
    await app.storage.providerProfiles.save(
      ProviderProfile(
        id: 'standard',
        name: 'Standard',
        type: ProviderType.anthropic,
        defaultModel: 'm',
        privacy: PrivacyLevel.local,
        authMethod: const ApiKeyAuth('provider.standard.apiKey'),
      ),
    );
    await app.storage.providerProfiles.setDefault('standard');
    await app.pump(tester);

    mark('find-ben');
    await sendMsg(tester, 'Ruf Ben an');
    await pumpUntil(tester, find.textContaining('Welcher Ben'));
    await waitIdle(tester);
    mark('find-anna');
    await sendMsg(tester, 'Nummer von Anna?');
    await pumpUntil(tester, find.textContaining('Annas Nummer'));
    await waitIdle(tester);

    mark('sms1-compose');
    await sendMsg(tester, 'Schreib Anna: Ich komme spaeter');
    await pumpUntil(tester, find.byKey(const ValueKey('smsText')));
    expect(find.textContaining('Anna Meier'), findsWidgets);
    expect(find.textContaining('5554'), findsWidgets);
    mark('sms1-preview-visible (wartet 6 s ohne Tipp)');
    await pumpFor(tester, const Duration(seconds: 6));
    mark('sms1-edit-and-send');
    await tester.enterText(
      find.byKey(const ValueKey('smsText')),
      'Ich komme spaeter EDIT',
    );
    await tester.pump();
    await tester.tap(find.text(l10n(tester).confYesSend));
    await pumpUntil(
      tester,
      find.textContaining('SMS erledigt', skipOffstage: false),
    );
    await waitIdle(tester);
    mark('sms1-done');

    mark('sms2-compose');
    await sendMsg(tester, 'Schreib Anna: NICHT SENDEN');
    await pumpUntil(tester, find.byKey(const ValueKey('smsText')));
    await pumpFor(tester, const Duration(seconds: 2));
    mark('sms2-cancel');
    await tester.tap(find.text(l10n(tester).confNoCancel));
    await pumpUntil(
      tester,
      find.textContaining('Abgebrochen.', skipOffstage: false),
    );
    await waitIdle(tester);
    mark('sms2-done');

    mark('call-compose');
    await sendMsg(tester, 'Ruf Ben Schmidt an');
    await pumpUntil(tester, find.text(l10n(tester).confYesCall));
    expect(find.textContaining('Ben Schmidt'), findsWidgets);
    expect(find.textContaining('5556'), findsWidgets);
    await pumpFor(tester, const Duration(seconds: 3));
    mark('call-yes');
    await tester.tap(find.text(l10n(tester).confYesCall));
    await pumpUntil(
      tester,
      find.textContaining('Anruf erledigt', skipOffstage: false),
    );
    await waitIdle(tester);
    mark('call-done');
  });
}
