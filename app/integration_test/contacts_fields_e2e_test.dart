// Gerätetest (WP164 A): Kanal `all` mit `fields` gegen das echte Adressbuch
// des Emulators. Der Host (E2E-Agent) legt vorher einen synthetischen Kontakt
// an: „Anna Meier“ mit Postanschrift „Musterstraße 1, 12345 Musterstadt“
// (privat), Geburtstag 1985-03-14 und Firma „Muster GmbH“, und erteilt die
// Kontakte-Berechtigung (adb shell pm grant app.wendelin
// android.permission.READ_CONTACTS).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/platform/channel_contacts_port.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Kontakte: nur angefragte Felder, unbekanntes Feld abgelehnt', (
    tester,
  ) async {
    const port = ChannelContactsPort();
    expect(await port.hasPermission(), isTrue, reason: 'READ_CONTACTS fehlt');

    // Search first (index), then extras for the hits only.
    const finder = ContactsFinder(port);
    final index = await port.all(fields: {ContactField.address});
    final plainAnna = index.singleWhere((c) => c.name == 'Anna Meier');
    expect(plainAnna.addresses, isEmpty, reason: 'Index ohne Zusatzdaten');
    expect(plainAnna.ref, isNotNull);

    final byAddress = await finder.find(
      'Anna Meier',
      fields: {ContactField.address},
    );
    final anna = byAddress.single;
    expect(anna.addresses.map((a) => a.address), [
      'Musterstraße 1, 12345 Musterstadt',
    ]);
    expect(anna.addresses.single.label, isNotEmpty);
    expect(anna.phones, isEmpty, reason: 'Telefon nicht angefragt');
    expect(anna.emails, isEmpty);
    expect(anna.birthday, isNull);
    expect(anna.organization, isNull);

    final more = await finder.find(
      'Anna Meier',
      fields: {ContactField.birthday, ContactField.organization},
    );
    final a2 = more.single;
    expect(a2.birthday, '1985-03-14');
    expect(a2.organization, 'Muster GmbH');
    expect(a2.addresses, isEmpty);

    final plain = await finder.find('Anna Meier');
    final a3 = plain.single;
    expect(a3.addresses, isEmpty);
    expect(a3.birthday, isNull);

    await expectLater(
      const MethodChannel(contactsChannelName).invokeMethod('details', {
        'ids': ['1'],
        'fields': ['phone'],
      }),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'bad_args'),
      ),
    );
    await expectLater(
      const MethodChannel(contactsChannelName).invokeMethod('all', {
        'fields': ['note'],
      }),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'bad_args'),
      ),
    );
  });
}
