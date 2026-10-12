import 'dart:async';

import 'package:test/test.dart';

import '../src/secret_store.dart';

/// Creates a fresh, empty store under test.
typedef SecretStoreFactory = FutureOr<SecretStore> Function();

/// Names of the checks in [secretStoreContractChecks].
abstract final class SecretStoreChecks {
  /// Empty store: no keys, reads return null.
  static const empty = 'leerer Store: keine Schlüssel, read liefert null';

  /// write then read returns the value.
  static const roundTrip = 'write und read liefern den Wert unverändert';

  /// write overwrites.
  static const overwrite = 'write überschreibt den alten Wert';

  /// Keys are independent.
  static const independent = 'Schlüssel sind unabhängig voneinander';

  /// delete removes, deleting a missing key is no error.
  static const delete = 'delete entfernt, fehlender Schlüssel ist kein Fehler';

  /// listKeys reflects writes and deletes.
  static const listKeys = 'listKeys spiegelt write und delete';

  /// Empty key is rejected.
  static const emptyKey = 'leerer Schlüssel wirft ArgumentError';
}

/// Reusable contract test suite for every [SecretStore] implementation
/// (`InMemorySecretStore`, the app's `flutter_secure_storage` store).
/// Registers one test per entry of [secretStoreContractChecks] in a group
/// labelled [name].
void secretStoreContract(
  SecretStoreFactory create, {
  String name = 'SecretStore',
}) {
  group('$name erfüllt SecretStore-Vertrag', () {
    secretStoreContractChecks(create).forEach(test);
  });
}

/// The individual checks of [secretStoreContract], keyed by the names in
/// [SecretStoreChecks]. Each check creates a fresh store and throws a
/// [TestFailure] on a contract violation, so tests can also run single checks
/// against deliberately broken stores.
Map<String, Future<void> Function()> secretStoreContractChecks(
  SecretStoreFactory create,
) {
  // Values that real backends tend to mangle.
  const tricky = {
    'provider.anthropic.apiKey': 'k-abc123',
    'oauth/spotify:token': 'äöü ß € 🎵 "quoted" \\ \n zweite Zeile',
    'leer': '',
    'rand': '  Leerzeichen am Rand\n',
    'lang': 'x',
  };
  final long = 'y' * 4096;

  return {
    SecretStoreChecks.empty: () async {
      final s = await create();
      expect(await s.listKeys(), isEmpty);
      expect(await s.read('fehlt'), isNull);
    },
    SecretStoreChecks.roundTrip: () async {
      final s = await create();
      for (final e in tricky.entries) {
        await s.write(e.key, e.key == 'lang' ? long : e.value);
      }
      for (final e in tricky.entries) {
        expect(
          await s.read(e.key),
          e.key == 'lang' ? long : e.value,
          reason: e.key,
        );
      }
    },
    SecretStoreChecks.overwrite: () async {
      final s = await create();
      await s.write('k', 'alt');
      await s.write('k', 'neu');
      expect(await s.read('k'), 'neu');
      expect(await s.listKeys(), {'k'});
    },
    SecretStoreChecks.independent: () async {
      final s = await create();
      await s.write('a', '1');
      await s.write('b', '2');
      await s.write('a', '3');
      await s.delete('a');
      expect(await s.read('b'), '2');
      expect(await s.read('a'), isNull);
    },
    SecretStoreChecks.delete: () async {
      final s = await create();
      await s.write('k', 'v');
      await s.delete('k');
      expect(await s.read('k'), isNull);
      await s.delete('k');
      await s.delete('nie-geschrieben');
      expect(await s.listKeys(), isEmpty);
    },
    SecretStoreChecks.listKeys: () async {
      final s = await create();
      await s.write('a', '1');
      await s.write('b', '');
      await s.write('c', '3');
      await s.delete('c');
      expect(await s.listKeys(), {'a', 'b'});
    },
    SecretStoreChecks.emptyKey: () async {
      final s = await create();
      await expectLater(() => s.write('', 'v'), throwsArgumentError);
      await expectLater(() => s.read(''), throwsArgumentError);
      await expectLater(() => s.delete(''), throwsArgumentError);
      expect(await s.listKeys(), isEmpty);
    },
  };
}
