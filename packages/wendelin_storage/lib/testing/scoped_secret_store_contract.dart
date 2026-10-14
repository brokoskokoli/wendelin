import 'package:test/test.dart';

import '../src/scoped_secret_store.dart';
import '../src/secret_store.dart';
import 'secret_store_contract.dart';

/// Names of the checks in [scopedSecretStoreContractChecks].
abstract final class ScopedSecretStoreChecks {
  /// The inner key is exactly `prefix + key`.
  static const innerKey = 'Schlüssel liegen byte-gleich unter Präfix + Name';

  /// Keys outside the prefix are neither listed nor readable.
  static const isolated = 'Schlüssel außerhalb des Präfixes bleiben unsichtbar';

  /// deleteAll deletes the own keys only.
  static const deleteAll = 'deleteAll löscht nur Schlüssel des Präfixes';

  /// deleteAll with a key prefix and keep set.
  static const deleteSome = 'deleteAll mit Teilpräfix und keep';
}

/// Contract of [ScopedSecretStore] over any inner [SecretStore] made by
/// [create]: the generic `secretStoreContract` on a view below [prefix]
/// plus the scope checks.
void scopedSecretStoreContract(
  SecretStore Function() create, {
  String prefix = 'scope.',
  String name = 'ScopedSecretStore',
}) {
  secretStoreContract(
    () => ScopedSecretStore(create(), prefix),
    name: name,
  );
  group('$name: Präfix-Vertrag', () {
    scopedSecretStoreContractChecks(create, prefix: prefix).forEach(test);
  });
}

/// The scope checks of [scopedSecretStoreContract], by name; each throws a
/// [TestFailure] on a violation.
Map<String, Future<void> Function()> scopedSecretStoreContractChecks(
  SecretStore Function() create, {
  String prefix = 'scope.',
}) => {
  ScopedSecretStoreChecks.innerKey: () async {
    final inner = create();
    final s = ScopedSecretStore(inner, prefix);
    await s.write('a.b', 'v');
    expect(await inner.listKeys(), {'${prefix}a.b'});
    expect(await inner.read('${prefix}a.b'), 'v');
    expect(await s.listKeys(), {'a.b'});
  },
  ScopedSecretStoreChecks.isolated: () async {
    final inner = create();
    await inner.write('fremd', 'x');
    await inner.write('${prefix}x'.substring(0, prefix.length - 1), 'y');
    await inner.write(prefix, 'nur-praefix');
    final s = ScopedSecretStore(inner, prefix);
    expect(await s.listKeys(), isEmpty);
    expect(await s.read('fremd'), isNull);
    expect(await s.read('../fremd'), isNull);
  },
  ScopedSecretStoreChecks.deleteAll: () async {
    final inner = create();
    await inner.write('fremd', 'x');
    final s = ScopedSecretStore(inner, prefix);
    await s.write('a', '1');
    await s.write('b.c', '2');
    await s.deleteAll();
    expect(await s.listKeys(), isEmpty);
    expect(await inner.listKeys(), {'fremd'});
  },
  ScopedSecretStoreChecks.deleteSome: () async {
    final s = ScopedSecretStore(create(), prefix);
    await s.write('id1.a', '1');
    await s.write('id1.b', '2');
    await s.write('id2.a', '3');
    await s.deleteAll(keyPrefix: 'id1.', keep: {'id1.b'});
    expect(await s.listKeys(), {'id1.b', 'id2.a'});
  },
};

