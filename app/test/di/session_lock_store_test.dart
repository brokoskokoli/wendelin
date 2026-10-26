import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/session_lock_store.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

void main() {
  late SettingsSessionLockStore store;
  late WendelinStorage storage;

  setUp(() {
    storage = openInMemoryStorage();
    store = SettingsSessionLockStore(storage.settings);
  });
  tearDown(() => storage.close());

  test('leer: keine Sperren', () async {
    expect(await store.load(), isEmpty);
  });

  test('Roundtrip: Sitzung -> Profil-Id', () async {
    await store.save({'s1': 'phala', 's2': ''});
    expect(await store.load(), {'s1': 'phala', 's2': ''});
  });

  test('leere Menge entfernt den Eintrag', () async {
    await store.save({'s1': 'phala'});
    await store.save({});
    expect(await storage.settings.get(AppSettings.sessionLocks), isNull);
    expect(await store.load(), isEmpty);
  });

  test('Nicht-String als Profil-Id: FormatException (fail-closed)', () async {
    await storage.settings.set(AppSettings.sessionLocks, {'s1': 7});
    await expectLater(store.load(), throwsFormatException);
  });

  test(
    'die Policy sperrt external, wenn der Speicher beschädigt ist',
    () async {
      await storage.settings.set(AppSettings.sessionLocks, {'s1': 7});
      final policy = RiskPolicy(lockStore: store);
      await policy.ready;
      expect(policy.isExternalLocked('irgendeine'), isTrue);
    },
  );
}
