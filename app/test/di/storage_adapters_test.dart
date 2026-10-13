import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/storage_adapters.dart';
import 'package:wendelin/platform/repository_memory_port.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart' as wi;
import 'package:wendelin_storage/fakes.dart';

void main() {
  test('Untergrenze privater Läufe: Port → Speicher → Retriever', () async {
    final storage = openInMemoryStorage();
    addTearDown(storage.close);
    final port = RepositoryMemoryPort(storage.memory);
    await port.save(
      'Knie-OP im März',
      category: wi.MemoryCategory.fact,
      source: 'session:s1',
      privacyFloor: PrivacyLevel.tee,
    );
    await port.save(
      'Knie ist wieder gut',
      category: wi.MemoryCategory.fact,
      source: 'session:s1',
    );
    final items = await StorageMemoryRetriever(storage.memory)
        .relevant('Knie', limit: 5);
    expect(
      {for (final i in items) i.text: i.privacyFloor},
      {'Knie-OP im März': PrivacyLevel.tee, 'Knie ist wieder gut': null},
    );
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
