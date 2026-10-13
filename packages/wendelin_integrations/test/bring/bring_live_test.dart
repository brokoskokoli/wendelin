@Tags(['live'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

// Live-Test gegen die echte (inoffizielle) Bring!-API, nur mit Testkonto:
//   set -a; . ~/.wendelin-live.env; set +a; dart test -t live --run-skipped \
//     test/bring/bring_live_test.dart
// Zugangsdaten nur aus BRING_EMAIL/BRING_PASSWORD, nie ausgeben. Legt einen
// Testartikel auf der Standardliste an und entfernt ihn wieder.

void main() {
  final email = Platform.environment['BRING_EMAIL'] ?? '';
  final password = Platform.environment['BRING_PASSWORD'] ?? '';
  final skip = email.isEmpty || password.isEmpty
      ? 'BRING_EMAIL/BRING_PASSWORD nicht gesetzt'
      : null;

  test('Login, Listen, Testartikel anlegen und entfernen', () async {
    final api = HttpBringApi();
    final auth = await api.login(email, password);
    final lists = await api.lists(auth);
    expect(lists, isNotEmpty);
    final listUuid = auth.defaultListUuid ?? lists.first.uuid;
    const item = BringItem(name: 'Wendelin Testartikel', spec: 'Live-Test');
    try {
      await api.saveItem(auth, listUuid, item);
      final after = await api.items(auth, listUuid);
      expect(after.purchase.map((i) => i.name), contains(item.name));
    } finally {
      await api.removeItem(auth, listUuid, item);
    }
    final cleaned = await api.items(auth, listUuid);
    expect(cleaned.purchase.map((i) => i.name), isNot(contains(item.name)));
    final fresh = await api.refresh(auth);
    expect(await api.lists(fresh), isNotEmpty);
  }, skip: skip);
}
