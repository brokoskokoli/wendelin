import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/storage_adapters.dart';
import 'package:wendelin/platform/repository_memory_port.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart'
    show StoredMemoryCategory;

void main() {
  test('Untergrenze privater Läufe: Port → Speicher → Retriever', () async {
    final storage = openInMemoryStorage();
    addTearDown(storage.close);
    final port = RepositoryMemoryPort(storage.memory);
    await port.save(
      'Knie-OP im März',
      category: MemoryCategory.fact,
      source: 'session:s1',
      privacyFloor: PrivacyLevel.tee,
    );
    await port.save(
      'Knie ist wieder gut',
      category: MemoryCategory.fact,
      source: 'session:s1',
    );
    final items = await StorageMemoryRetriever(storage.memory)
        .relevant('Knie', limit: 5);
    expect(
      {for (final i in items) i.text: i.privacyFloor},
      {'Knie-OP im März': PrivacyLevel.tee, 'Knie ist wieder gut': null},
    );
  });

  test('Retriever sieht nur den eigenen Namespace (WP92b)', () async {
    final storage = openInMemoryStorage();
    addTearDown(storage.close);
    for (final (owner, text) in const [
      ('', 'Knie Standard'),
      ('p:a', 'Knie Anna'),
      ('p:b', 'Knie Ben'),
    ]) {
      await storage.memory.save(
        text,
        category: StoredMemoryCategory.fact,
        source: 'user',
        owner: owner,
      );
    }
    Future<List<String>> texts(String owner) async => [
      for (final i in await StorageMemoryRetriever(
        storage.memory,
        owner: owner,
      ).relevant('Knie', limit: 5))
        i.text,
    ];
    expect(await texts(''), ['Knie Standard']);
    expect(await texts('p:a'), ['Knie Anna']);
    expect(await texts('p:zzz'), isEmpty);
  });

  test('Gesprächszüge behalten ihre Untergrenze', () async {
    final storage = openInMemoryStorage();
    addTearDown(storage.close);
    final session = await storage.conversations.startNew(DateTime.utc(2026));
    final conversation = StorageConversation(storage.conversations, session.id);
    await conversation.record(
      Message.user('privat: x').withPrivacyFloor(PrivacyLevel.tee),
    );
    final back = await conversation.recentMessages(turns: 1);
    expect(back.single.privacyFloor, PrivacyLevel.tee);
  });
}
