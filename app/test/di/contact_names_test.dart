import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/hint_term_providers.dart';
import 'package:wendelin/di/integration_providers.dart';

import '../support/test_env.dart';

/// Hint names from the address book (WP85): only with the integration on and
/// the permission granted, names only.
void main() {
  Future<List<String>> names(TestEnv env) async {
    final c = env.container();
    addTearDown(c.dispose);
    return c.read(contactNamesProvider)();
  }

  test('an: Anzeigenamen, ohne Nummern', () async {
    final env = TestEnv(enabled: const {'contacts'});
    expect(await names(env), ['Anna Meier', 'Ben Schmidt', 'Ben Weber']);
  });

  test(
    'Integration aus: leer, der Adressbuchzugriff wird nicht berührt',
    () async {
      final env = TestEnv();
      expect(await names(env), isEmpty);
      expect(env.contacts.methodCalls, isNot(contains('all')));
    },
  );

  test('ohne READ_CONTACTS oder bei Portfehler: leer', () async {
    final denied = TestEnv(enabled: const {'contacts'})
      ..contacts.permission = false;
    expect(await names(denied), isEmpty);
    // Das Adressbuch wird ohne Berechtigung gar nicht erst gelesen.
    expect(denied.contacts.methodCalls, isNot(contains('all')));
    final broken = TestEnv(enabled: const {'contacts'})
      ..contacts.failNext('all');
    expect(await names(broken), isEmpty);
  });

  test(
    'Einschalten baut die Namen neu, Namen tauchen als Hinweis auf',
    () async {
      final env = TestEnv();
      final c = env.container();
      addTearDown(c.dispose);
      expect(
        await c.read(hintTermsProvider.future),
        isNot(contains('Anna Meier')),
      );
      c
          .read(enabledIntegrationsProvider.notifier)
          .set('contacts', enabled: true);
      expect(await c.read(hintTermsProvider.future), contains('Anna Meier'));
    },
  );
}
