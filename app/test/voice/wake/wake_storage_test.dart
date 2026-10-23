import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

WakeTemplates templates(String id) => WakeTemplates(
  speakerId: id,
  featureVersion: 'v1',
  threshold: 0.9,
  embeddings: [
    Float32List.fromList([1, 2, 3]),
    Float32List.fromList([4, 5, 6]),
  ],
);

void main() {
  late InMemorySecretStore secrets;
  late SecretWakeTemplateStore store;
  setUp(() {
    secrets = InMemorySecretStore();
    store = SecretWakeTemplateStore(secrets);
  });

  test('Vorlagen und Sprecher überstehen den Roundtrip', () async {
    await store.save(templates('a'));
    await store.saveSpeakers(const [WakeSpeaker(id: 'a', name: 'Anna')]);
    final back = (await store.load('a'))!;
    expect(back.embeddings.map((e) => e.toList()), [
      [1.0, 2.0, 3.0],
      [4.0, 5.0, 6.0],
    ]);
    expect(back.threshold, 0.9);
    expect((await store.speakers()).single.name, 'Anna');
    expect(await store.load('b'), isNull);
  });

  test('liegt im verschlüsselten SecretStore, nur Embeddings', () async {
    await store.save(templates('a'));
    final raw = jsonDecode(
      (await secrets.read('wake.templates.a'))!,
    ) as Map<String, Object?>;
    expect(raw.keys, {
      'speakerId',
      'featureVersion',
      'threshold',
      'embeddings',
    });
  });

  test('beschädigte Daten gelten als „nicht eingelernt“', () async {
    await secrets.write('wake.templates.a', '{kaputt');
    await secrets.write('wake.speakers', 'nein');
    expect(await store.load('a'), isNull);
    expect(await store.speakers(), isEmpty);
  });

  test(
    'deleteAll entfernt Vorlagen und Sprecherliste, nichts anderes',
    () async {
      await store.save(templates('a'));
      await store.save(templates('b'));
      await store.saveSpeakers(const [WakeSpeaker(id: 'a', name: '')]);
      await secrets.write('provider.key', 'geheim');
      await store.deleteAll();
      expect(await secrets.listKeys(), {'provider.key'});
    },
  );

  test('delete entfernt nur einen Sprecher', () async {
    await store.save(templates('a'));
    await store.save(templates('b'));
    await store.delete('a');
    expect(await store.load('a'), isNull);
    expect(await store.load('b'), isNotNull);
  });
}
