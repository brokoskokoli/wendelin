import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/speaker/person_scope.dart';
import 'package:wendelin/voice/speaker/person_storage.dart';
import 'package:wendelin/voice/speaker/speaker_storage.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../agent/person_scope_test.dart' show testProfile;

void main() {
  late InMemorySecretStore secrets;
  late SecretPersonSettingsStore store;
  setUp(() {
    secrets = InMemorySecretStore();
    store = SecretPersonSettingsStore(secrets);
  });

  group('SecretPersonSettingsStore (WP92b)', () {
    test(
      'Roundtrip, Ersetzen, Löschen; ein Schlüssel im SecretStore',
      () async {
        await store.save(const PersonSettings(personId: 'a', address: 'Anni'));
        await store.save(const PersonSettings(personId: 'b'));
        await store.save(const PersonSettings(personId: 'a', address: 'Anna'));
        final all = await store.load();
        expect(all['a']!.address, 'Anna');
        expect(all.keys, unorderedEquals(['a', 'b']));
        expect(await secrets.listKeys(), [
          SecretPersonSettingsStore.settingsKey,
        ]);
        await store.delete('a');
        await store.delete('gibtsnicht');
        expect((await store.load()).keys, ['b']);
        await store.delete('b');
        expect(await secrets.listKeys(), isEmpty);
      },
    );

    test('clear und kaputtes JSON', () async {
      await store.save(const PersonSettings(personId: 'a'));
      await store.clear();
      expect(await secrets.listKeys(), isEmpty);
      await secrets.write(SecretPersonSettingsStore.settingsKey, '{kaputt');
      expect(await store.load(), isEmpty);
      await secrets.write(
        SecretPersonSettingsStore.settingsKey,
        '[1,{"personId":"x"}]',
      );
      expect((await store.load()).keys, ['x']);
    });
  });

  group('PersonScopeResolver', () {
    late PersonScopeResolver resolver;
    setUp(() async {
      await SecretSpeakerProfileStore(secrets).save(testProfile('a', ' Anna '));
      resolver = PersonScopeResolver(
        profiles: SecretSpeakerProfileStore(secrets),
        settings: store,
      );
    });

    test('keine Person: Standard', () async {
      expect(await resolver.scopeOf(null), PersonScope.standard);
      expect(await resolver.scopeOf('weg'), PersonScope.standard);
      expect(PersonScope.standard.memoryOwner, '');
      expect(PersonScope.standard.address, isNull);
    });

    test('ohne Einstellungen: Name als Anrede, eigener Namespace', () async {
      final s = await resolver.scopeOf('a');
      expect(
        (s.address, s.memoryOwner, s.agentProfileId),
        ('Anna', 'p:a', null),
      );
    });

    test('mit Einstellungen', () async {
      await store.save(
        const PersonSettings(
          personId: 'a',
          address: '  Anni ',
          sharedMemory: true,
          agentProfileId: 'claude',
        ),
      );
      final s = await resolver.scopeOf('a');
      expect(
        (s.address, s.memoryOwner, s.agentProfileId),
        ('Anni', '', 'claude'),
      );
      expect(s.isStandard, isFalse);
    });

    test('Lesefehler: Standard, blockiert nie', () async {
      final broken = PersonScopeResolver(
        profiles: _Throwing(),
        settings: store,
      );
      expect(await broken.scopeOf('a'), PersonScope.standard);
    });

    test('toString enthält keine Daten', () async {
      await store.save(const PersonSettings(personId: 'a', address: 'Anni'));
      final text = '${await resolver.scopeOf('a')}';
      expect(text, isNot(contains('Anni')));
      expect(text, isNot(contains('p:a')));
    });
  });
}

final class _Throwing implements SpeakerProfileStore {
  @override
  Future<List<SpeakerProfile>> load() => Future.error(StateError('x'));
  @override
  Future<void> save(SpeakerProfile profile) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> clear() async {}
}
