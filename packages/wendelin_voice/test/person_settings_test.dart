import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  group('PersonSettings (WP92b)', () {
    test('Standard: eigenes Gedächtnis, keine Anrede, Standard-Agent', () {
      const s = PersonSettings(personId: 'a');
      expect(s.sharedMemory, isFalse);
      expect(s.memoryOwner, 'p:a');
      expect(s.address, isNull);
      expect(s.agentProfileId, isNull);
    });

    test('geteiltes Gedächtnis = Standard-Namespace', () {
      expect(
        const PersonSettings(personId: 'a', sharedMemory: true).memoryOwner,
        '',
      );
    });

    test('JSON-Runde und kaputte Einträge', () {
      const s = PersonSettings(
        personId: 'a',
        address: 'Mia',
        sharedMemory: true,
        agentProfileId: 'claude',
      );
      expect(PersonSettings.fromJson(s.toJson()), s);
      expect(PersonSettings.fromJson('x'), isNull);
      expect(PersonSettings.fromJson({'personId': ''}), isNull);
      expect(PersonSettings.fromJson({'sharedMemory': true}), isNull);
    });

    test('copyWith kann Anrede und Agent löschen', () {
      const s = PersonSettings(
        personId: 'a',
        address: 'S',
        agentProfileId: 'x',
      );
      final c = s.copyWith(clearAddress: true, clearAgent: true);
      expect((c.address, c.agentProfileId), (null, null));
    });

    test('toString enthält weder Anrede noch Id', () {
      const s = PersonSettings(personId: 'geheim-id', address: 'Geheimname');
      expect('$s', isNot(contains('geheim')));
      expect('$s', isNot(contains('Geheimname')));
    });

    test('InMemoryPersonSettingsStore: save, load, delete, clear', () async {
      final store = InMemoryPersonSettingsStore();
      await store.save(const PersonSettings(personId: 'a', address: 'A'));
      await store.save(const PersonSettings(personId: 'b'));
      expect((await store.load()).keys, unorderedEquals(['a', 'b']));
      await store.delete('a');
      expect((await store.load()).keys, ['b']);
      await store.clear();
      expect(await store.load(), isEmpty);
    });
  });
}
