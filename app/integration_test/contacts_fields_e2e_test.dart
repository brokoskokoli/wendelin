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

    final byAddress = await port.all(fields: {ContactField.address});
    final anna = byAddress.singleWhere((c) => c.name == 'Anna Meier');
    expect(anna.addresses.map((a) => a.address), [
      'Musterstraße 1, 12345 Musterstadt',
    ]);
    expect(anna.addresses.single.label, isNotEmpty);
    for (final c in byAddress) {
      expect(c.phones, isEmpty, reason: 'Telefon nicht angefragt');
      expect(c.emails, isEmpty);
      expect(c.birthday, isNull);
      expect(c.organization, isNull);
    }

    final more = await port.all(
      fields: {ContactField.birthday, ContactField.organization},
    );
    final a2 = more.singleWhere((c) => c.name == 'Anna Meier');
    expect(a2.birthday, '1985-03-14');
    expect(a2.organization, 'Muster GmbH');
    expect(a2.addresses, isEmpty);

    final plain = await port.all();
    final a3 = plain.singleWhere((c) => c.name == 'Anna Meier');
    expect(a3.addresses, isEmpty);
    expect(a3.birthday, isNull);

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
