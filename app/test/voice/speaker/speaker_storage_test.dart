import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/speaker/speaker_storage.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

SpeakerProfile profile(String id, String name) => SpeakerProfile(
  id: id,
  name: name,
  embeddings: [
    Float32List.fromList([1, 0, 0]),
    Float32List.fromList([0.9, 0.1, 0]),
  ],
  threshold: 0.5,
  createdAt: DateTime.utc(2026, 10, 19),
);

void main() {
  late InMemorySecretStore secrets;
  late SecretSpeakerProfileStore store;
  setUp(() {
    secrets = InMemorySecretStore();
    store = SecretSpeakerProfileStore(secrets);
  });

  test('Roundtrip, Ersetzen und Löschen einzelner Personen', () async {
    await store.save(profile('a', 'Anna'));
    await store.save(profile('b', 'Ben'));
    await store.save(profile('a', 'Anna 2'));
    final all = await store.load();
    expect(all.map((p) => p.name), ['Ben', 'Anna 2']);
    expect(all.last.embeddings.length, 2);
    await store.delete('b');
    await store.delete('gibtsnicht');
    expect((await store.load()).single.id, 'a');
  });

  test('liegt nur unter einem Schlüssel im SecretStore', () async {
    await store.save(profile('a', 'Anna'));
    expect(await secrets.listKeys(), [SecretSpeakerProfileStore.profilesKey]);
  });

  test('clear entfernt alles, auch der letzte delete', () async {
    await store.save(profile('a', 'Anna'));
    await store.clear();
    expect(await secrets.listKeys(), isEmpty);
    await store.save(profile('a', 'Anna'));
    await store.delete('a');
    expect(await secrets.listKeys(), isEmpty);
  });

  test('kaputtes JSON oder Einträge verhalten sich wie leer', () async {
    await secrets.write(SecretSpeakerProfileStore.profilesKey, '{kaputt');
    expect(await store.load(), isEmpty);
    await secrets.write(
      SecretSpeakerProfileStore.profilesKey,
      '[1,{"id":"x"}]',
    );
    expect(await store.load(), isEmpty);
  });
}
