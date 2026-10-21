import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

void main() {
  late FakeContactsPort book;
  late FakePhonePort phone;
  late SmsDraftEdits edits;
  late ContactsIntegration integration;
  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);

  setUp(() {
    book = FakeContactsPort(
      contacts: const [
        ContactEntry(
          name: 'Anna Meier',
          phones: [
            ContactPhone('+49 170 1234567', label: 'Mobil'),
            ContactPhone('030 555-0100', label: 'Arbeit'),
          ],
          emails: ['anna@example.org'],
        ),
        ContactEntry(
          name: 'Anna Schmidt',
          phones: [ContactPhone('0171 7654321')],
        ),
        ContactEntry(name: 'Jürgen Özdemir', phones: [ContactPhone('040 123')]),
        ContactEntry(name: 'Anna', phones: [ContactPhone('0152 111222')]),
        ContactEntry(name: 'Johanna', phones: [ContactPhone('0160 999')]),
      ],
    );
    phone = FakePhonePort();
    edits = SmsDraftEdits();
    integration = ContactsIntegration(book, phone, edits: edits);
  });

  group('Metadaten', () {
    test('sensibel, Android, Risiken, Berechtigungsschritt', () async {
      expect(integration.id, 'contacts');
      expect(integration.sensitive, isTrue);
      expect(integration.platforms, {AppPlatform.android});
      expect(
        {for (final t in integration.tools) t.name: t.risk},
        {
          'contacts__find': RiskLevel.read,
          'sms__compose': RiskLevel.external,
          'phone__call': RiskLevel.external,
        },
      );
      expect((await integration.setupState()).missingSteps, isEmpty);
      book.permission = false;
      expect((await integration.setupState()).missingSteps, [
        ContactsIntegration.permissionStep,
      ]);
    });
  });

  group('Kontaktsuche', () {
    test(
      'findet ohne Beachtung von Umlauten und Groß-/Kleinschreibung',
      () async {
        final o = await tool('contacts__find')
            .execute({'query': 'jurgen OZDEMIR'}, ctx());
        final m = json(o)['matches']! as List<Object?>;
        expect(m, hasLength(1));
        expect((m.single! as Map)['name'], 'Jürgen Özdemir');
        expect(json(o)['choice_needed'], isFalse);
      },
    );

    test('Wortanfang, kein Teilwort: Anna findet nicht Johanna', () async {
      final finder = ContactsFinder(book);
      book.contacts = book.contacts.where((c) => c.name != 'Anna').toList();
      final names = [for (final c in await finder.find('anna')) c.name];
      expect(names, ['Anna Meier', 'Anna Schmidt']);
    });

    test('genauer Name gewinnt vor Teiltreffern', () async {
      final names = [
        for (final c in await ContactsFinder(book).find('Anna')) c.name,
      ];
      expect(names, ['Anna']);
    });

    test('Mehrdeutigkeit: mehrere Treffer verlangen Rückfrage', () async {
      book.contacts = book.contacts.where((c) => c.name != 'Anna').toList();
      final o = await tool('contacts__find').execute({'query': 'Anna'}, ctx());
      expect(json(o)['choice_needed'], isTrue);
      expect(json(o)['hint'], contains('Ask the user'));
      expect((json(o)['matches']! as List), hasLength(2));
    });

    test('Mehrdeutigkeit: ein Kontakt mit zwei Nummern', () async {
      final o = await tool('contacts__find')
          .execute({'query': 'Anna Meier'}, ctx());
      expect(json(o)['choice_needed'], isTrue);
      final m = (json(o)['matches']! as List).single! as Map;
      expect((m['phones']! as List), hasLength(2));
      expect(m['emails'], ['anna@example.org']);
    });

    test('kein Treffer ist kein Fehler', () async {
      final o = await tool('contacts__find').execute({'query': 'Zorro'}, ctx());
      expect(o.isError, isFalse);
      expect(json(o)['matches'], isEmpty);
    });

    test('ohne Berechtigung: Tool-Fehler mit Hinweis', () async {
      book.permission = false;
      final o = await tool('contacts__find').execute({'query': 'Anna'}, ctx());
      expect(o.isError, isTrue);
    });

    test('Telefonnummern: Landesvorwahl und national gelten als gleich', () {
      expect(samePhone('+49 170 1234567', '0170 1234567'), isTrue);
      expect(samePhone('0049 170 1234567', '+491701234567'), isTrue);
      expect(samePhone('0170 1234567', '0170 1234568'), isFalse);
      // Different country code, same trailing digits: not the same line.
      expect(samePhone('+44 701234567', '0170 1234567'), isFalse);
      expect(samePhone('+44 170 1234567', '+49 170 1234567'), isFalse);
      // Edge cases: a stray prefix or short number is never the same line.
      expect(samePhone('+1701234567', '01701234567'), isFalse);
      expect(samePhone('+99991701234567', '01701234567'), isFalse);
      expect(samePhone('+4911', '011'), isFalse);
      expect(samePhone('0123456', '90123456'), isFalse);
      // Rest length 5 is too short to match, 6 is the minimum.
      expect(samePhone('+4912345', '012345'), isFalse);
      expect(samePhone('+49123456', '0123456'), isTrue);
      expect(cleanPhoneNumber('+49 (170) 123-4567'), '+491701234567');
      expect(cleanPhoneNumber('Anna'), isNull);
      expect(cleanPhoneNumber('12'), isNull);
    });
  });

  group('sms__compose', () {
    test(
      'Bestätigungstext nennt Name aus dem Adressbuch, nicht vom Modell',
      () async {
        final t = tool('sms__compose') as ConfirmationPreparer;
        final text = await t.prepareConfirmation({
          'to': '0170 1234567',
          'text': 'Bin gleich da',
        }, ctx());
        expect(text, 'SMS an Anna Meier (01701234567)\nBin gleich da');
        final unknown = await t.prepareConfirmation({
          'to': '+4915100000',
          'text': 'Hi',
        }, ctx());
        expect(unknown, 'SMS an +4915100000\nHi');
      },
    );

    test('Vorbereiten sendet nie', () async {
      await (tool('sms__compose') as ConfirmationPreparer).prepareConfirmation({
        'to': '0170 1234567',
        'text': 'x',
      }, ctx());
      expect(phone.sent, isEmpty);
    });

    test('sendet genau den Text', () async {
      final o = await tool(
        'sms__compose',
      ).execute({'to': '+49 170 1234567', 'text': '  Bin gleich da '}, ctx());
      expect(o.isError, isFalse);
      expect(o.text, contains('Anna Meier'));
      expect(phone.sent, [(number: '+491701234567', text: 'Bin gleich da')]);
    });

    test(
      'der bestätigte, geänderte Text wird gesendet, genau einmal',
      () async {
        edits.set('+491701234567', 'Bin gleich da', 'Bin in 5 Minuten da');
        expect(edits.isEdited('+49 170 1234567', 'Bin gleich da'), isTrue);
        await tool('sms__compose')
            .execute({'to': '+49 170 1234567', 'text': 'Bin gleich da'}, ctx());
        expect(phone.sent.single.text, 'Bin in 5 Minuten da');
        await tool('sms__compose')
            .execute({'to': '+49 170 1234567', 'text': 'Bin gleich da'}, ctx());
        expect(phone.sent.last.text, 'Bin gleich da');
      },
    );

    test('Änderung zurück auf das Original entfernt sie', () {
      edits
        ..set('1', 'a', 'b')
        ..set('1', 'a', 'a');
      expect(edits.isEdited('1', 'a'), isFalse);
    });

    test('Änderung gilt nicht für andere Empfänger oder Texte', () async {
      edits.set('+491701234567', 'Bin gleich da', 'Anderer Text');
      await tool('sms__compose')
          .execute({'to': '0171 7654321', 'text': 'Bin gleich da'}, ctx());
      expect(phone.sent.single.text, 'Bin gleich da');
    });

    test('ungültige Nummer, leerer und zu langer Text sind Fehler, nichts gesendet', () async {
      for (final args in <Map<String, Object?>>[
        {'to': 'Anna', 'text': 'Hi'},
        {'to': '0170 1234567', 'text': '   '},
        {'to': '0170 1234567', 'text': 'x' * (maxSmsChars + 1)},
      ]) {
        final o = await tool('sms__compose').execute(args, ctx());
        expect(o.isError, isTrue, reason: '$args');
      }
      expect(phone.sent, isEmpty);
    });

    test('geänderter Text über dem Limit: Fehler, nichts gesendet', () async {
      edits.set('+491701234567', 'Hi', 'x' * (maxSmsChars + 1));
      final o = await tool('sms__compose')
          .execute({'to': '+49 170 1234567', 'text': 'Hi'}, ctx());
      expect(o.isError, isTrue);
      expect(phone.sent, isEmpty);
    });

    test('leerer geänderter Text: Fehler, nichts gesendet', () async {
      edits.set('+491701234567', 'Hi', '');
      final o = await tool('sms__compose')
          .execute({'to': '+49 170 1234567', 'text': 'Hi'}, ctx());
      expect(o.isError, isTrue);
      expect(phone.sent, isEmpty);
    });

    test('ohne SMS-Berechtigung: Fehler, nichts gesendet', () async {
      phone.smsAllowed = false;
      final o = await tool('sms__compose')
          .execute({'to': '0170 1234567', 'text': 'Hi'}, ctx());
      expect(o.isError, isTrue);
      // The permission is checked before sending, not found out by sending.
      expect(phone.methodCalls, isNot(contains('sendSms')));
      expect(o.text, contains('Berechtigung'));
      expect(phone.sent, isEmpty);
    });

    test('Audit: Empfängername, nie der Text', () async {
      final t = tool('sms__compose') as AuditArgumentsRedactor;
      final s = await t.redactedArguments({
        'to': '0170 1234567',
        'text': 'Geheimer Text',
      }, ctx());
      expect(s, '{"recipient":"Anna Meier"}');
      final viaTool = await tool('sms__compose').auditArguments(
        '{"to":"0170 1234567","text":"Geheimer Text"}',
        {'to': '0170 1234567', 'text': 'Geheimer Text'},
        ctx(),
      );
      expect(viaTool, isNot(contains('Geheimer')));
    });
  });

  group('phone__call', () {
    test('Bestätigungstext mit Name und Nummer', () async {
      final text = await (tool('phone__call') as ConfirmationPreparer)
          .prepareConfirmation({'to': '030 555-0100'}, ctx());
      expect(text, 'Anrufen: Anna Meier (0305550100)');
      expect(phone.called, isEmpty);
    });

    test('mit CALL_PHONE direkt, sonst Wählbildschirm', () async {
      var o = await tool('phone__call').execute({'to': '030 555-0100'}, ctx());
      expect(phone.called, ['0305550100']);
      expect(o.text, contains('gestartet'));
      phone.callAllowed = false;
      o = await tool('phone__call').execute({'to': '030 555-0100'}, ctx());
      expect(phone.dialed, ['0305550100']);
      expect(o.text, contains('Wählbildschirm'));
    });

    test('keine Nummer: Fehler, kein Anruf', () async {
      final o = await tool('phone__call').execute({'to': 'Anna'}, ctx());
      expect(o.isError, isTrue);
      expect(phone.called + phone.dialed, isEmpty);
    });

    test('Audit: nur Empfängername', () async {
      final s = await (tool('phone__call') as AuditArgumentsRedactor)
          .redactedArguments({'to': '0305550100'}, ctx());
      expect(s, '{"recipient":"Anna Meier"}');
    });
  });

  group('feste Bestätigung', () {
    test('SMS gesendet: Name aus dem Adressbuch', () async {
      final t = tool('sms__compose');
      final o = await t.execute({'to': '0170 1234567', 'text': 'Hallo'}, ctx());
      expectFixed(
        o,
        t,
        'sms.sent',
        de: 'Die SMS an Anna Meier wurde gesendet.',
      );
    });

    test('SMS ohne Berechtigung → Fehler ohne Satz', () async {
      phone.smsAllowed = false;
      final o = await tool('sms__compose')
          .execute({'to': '0170 1234567', 'text': 'Hallo'}, ctx());
      expect(o.isError, isTrue);
      expect(o.fixed, isNull);
    });

    test('Anruf direkt gestartet', () async {
      final t = tool('phone__call');
      final o = await t.execute({'to': '030 555-0100'}, ctx());
      expectFixed(
        o,
        t,
        'call.started',
        de: 'Der Anruf bei Anna Meier wurde gestartet.',
      );
    });

    test('Anruf nur als Wählbildschirm → kein Satz', () async {
      phone.callAllowed = false;
      final o = await tool('phone__call')
          .execute({'to': '030 555-0100'}, ctx());
      expect(o.isError, isFalse);
      expect(o.text, contains('Wählbildschirm'));
      expect(o.fixed, isNull);
    });

    test('Anruf ohne Nummer → Fehler ohne Satz', () async {
      final o = await tool('phone__call').execute({'to': 'Anna'}, ctx());
      expect(o.isError, isTrue);
      expect(o.fixed, isNull);
    });
  });
}
