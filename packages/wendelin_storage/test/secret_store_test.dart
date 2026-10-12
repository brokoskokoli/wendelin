import 'package:test/test.dart';
import 'package:wendelin_storage/testing.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// A store with switchable defects. Without defects it is correct, which
/// proves the failures below come from the defect alone.
final class _DefectiveStore implements SecretStore {
  _DefectiveStore({
    this.trims = false,
    this.keepsOnDelete = false,
    this.throwsOnMissingDelete = false,
    this.firstWriteWins = false,
    this.listsDeleted = false,
    this.acceptsEmptyKey = false,
    this.dropsEmptyValue = false,
  });

  final bool trims;
  final bool keepsOnDelete;
  final bool throwsOnMissingDelete;
  final bool firstWriteWins;
  final bool listsDeleted;
  final bool acceptsEmptyKey;
  final bool dropsEmptyValue;

  final _values = <String, String>{};
  final _everWritten = <String>{};

  void _check(String key) {
    if (key.isEmpty && !acceptsEmptyKey) throw ArgumentError('leer');
  }

  @override
  Future<String?> read(String key) async {
    _check(key);
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _check(key);
    if (dropsEmptyValue && value.isEmpty) return;
    if (firstWriteWins && _values.containsKey(key)) return;
    _values[key] = trims ? value.trim() : value;
    _everWritten.add(key);
  }

  @override
  Future<void> delete(String key) async {
    _check(key);
    if (throwsOnMissingDelete && !_values.containsKey(key)) {
      throw StateError('fehlt');
    }
    if (!keepsOnDelete) _values.remove(key);
  }

  @override
  Future<Set<String>> listKeys() async =>
      listsDeleted ? Set.of(_everWritten) : Set.of(_values.keys);
}

void main() {
  secretStoreContract(InMemorySecretStore.new, name: 'InMemorySecretStore');
  secretStoreContract(_DefectiveStore.new, name: 'fehlerfreier Teststore');

  test('InMemorySecretStore: Startwerte werden kopiert', () async {
    final initial = {'a': '1'};
    final s = InMemorySecretStore(initial);
    initial['b'] = '2';
    expect(await s.listKeys(), {'a'});
    expect(await s.read('a'), '1');
  });

  group('Contract erkennt defekte Stores', () {
    Future<void> expectFails(SecretStore Function() create, String check) {
      final run = secretStoreContractChecks(create)[check]!;
      // Any exception fails the registered test; usually a TestFailure.
      return expectLater(run(), throwsA(anything));
    }

    test('verändert Werte', () async {
      await expectFails(
        () => _DefectiveStore(trims: true),
        SecretStoreChecks.roundTrip,
      );
    });
    test('verliert leere Werte', () async {
      await expectFails(
        () => _DefectiveStore(dropsEmptyValue: true),
        SecretStoreChecks.roundTrip,
      );
      await expectFails(
        () => _DefectiveStore(dropsEmptyValue: true),
        SecretStoreChecks.listKeys,
      );
    });
    test('überschreibt nicht', () async {
      await expectFails(
        () => _DefectiveStore(firstWriteWins: true),
        SecretStoreChecks.overwrite,
      );
    });
    test('delete wirkt nicht', () async {
      await expectFails(
        () => _DefectiveStore(keepsOnDelete: true),
        SecretStoreChecks.delete,
      );
      await expectFails(
        () => _DefectiveStore(keepsOnDelete: true),
        SecretStoreChecks.independent,
      );
    });
    test('delete eines fehlenden Schlüssels wirft', () async {
      await expectFails(
        () => _DefectiveStore(throwsOnMissingDelete: true),
        SecretStoreChecks.delete,
      );
    });
    test('listKeys zeigt gelöschte Schlüssel', () async {
      await expectFails(
        () => _DefectiveStore(listsDeleted: true),
        SecretStoreChecks.listKeys,
      );
    });
    test('leerer Schlüssel wird angenommen', () async {
      await expectFails(
        () => _DefectiveStore(acceptsEmptyKey: true),
        SecretStoreChecks.emptyKey,
      );
    });
  });
}
