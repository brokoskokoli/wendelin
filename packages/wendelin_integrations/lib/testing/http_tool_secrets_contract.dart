import 'dart:async';

import 'package:test/test.dart';

import '../src/http_tools/http_transport.dart';

/// Creates the [HttpToolSecrets] under test holding exactly [values]
/// (reference → secret).
typedef HttpToolSecretsFactory = FutureOr<HttpToolSecrets> Function(
  Map<String, String> values,
);

/// Contract every [HttpToolSecrets] implementation must pass (the fake and
/// the app's `SecretStore` adapter).
void httpToolSecretsContract(String name, HttpToolSecretsFactory create) {
  group('HttpToolSecrets-Vertrag: $name', () {
    test('liefert gespeicherte Werte unverändert', () async {
      const tricky = 'Bearer ä/+=%20 "x"';
      final s = await create({'ha': 'abc123', 'tricky': tricky});
      expect(await s.read('ha'), 'abc123');
      expect(await s.read('tricky'), tricky);
    });

    test('unbekannte Referenz ergibt null statt Fehler', () async {
      final s = await create({'ha': 'abc123'});
      expect(await s.read('fehlt'), isNull);
      expect(await s.read(''), isNull);
    });

    test('toString verrät keine Werte', () async {
      final s = await create({'ha': 'kanarienvogel-4711'});
      expect(s.toString(), isNot(contains('kanarienvogel-4711')));
    });
  });
}
