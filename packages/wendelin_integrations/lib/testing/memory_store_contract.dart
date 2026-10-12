import 'dart:async';

import 'package:test/test.dart';

import '../src/common/port_exception.dart';
import '../src/memory/memory.dart';

/// Creates an **empty** [MemoryStorePort] under test.
typedef MemoryStoreFactory = FutureOr<MemoryStorePort> Function();

/// Names of the checks in [memoryStoreContractChecks].
abstract final class MemoryStoreChecks {
  /// save returns the stored entry with a new id.
  static const save = 'save liefert Eintrag mit Id, Text, Kategorie und Quelle';

  /// list returns newest first.
  static const listOrder = 'list: neueste zuerst';

  /// search finds matching entries and respects the limit.
  static const search = 'search findet passende Einträge, respektiert limit';

  /// search marks hits as used.
  static const searchMarksUsed = 'search markiert Treffer als genutzt';

  /// forget removes and returns the entry; unknown ids are notFound.
  static const forget =
      'forget entfernt und liefert den Eintrag; unbekannt ist notFound';

  /// Sensitive content is rejected and not stored.
  static const sensitive = 'sensible Inhalte werden abgewiesen';

  /// Blank text throws ArgumentError.
  static const blank = 'leerer Text wirft ArgumentError';
}

/// Reusable contract suite for every [MemoryStorePort] implementation
/// (`FakeMemoryStore`, the app's repository-backed port); registers one
/// test per entry of [memoryStoreContractChecks].
void memoryStoreContract(
  MemoryStoreFactory create, {
  String name = 'MemoryStorePort',
}) {
  group('$name erfüllt den MemoryStorePort-Vertrag', () {
    memoryStoreContractChecks(create).forEach(test);
  });
}

/// The checks of [memoryStoreContract] by name ([MemoryStoreChecks]).
Map<String, Future<void> Function()> memoryStoreContractChecks(
  MemoryStoreFactory create,
) {
  Future<MemoryEntry> fact(MemoryStorePort s, String text) =>
      s.save(text, category: MemoryCategory.fact, source: 'contract');

  return {
    MemoryStoreChecks.save: () async {
      final s = await create();
      final e = await s.save(
        'Mag keinen Koriander',
        category: MemoryCategory.preference,
        source: 'session:s1',
      );
      expect(e.id, isNotEmpty);
      expect(e.text, 'Mag keinen Koriander');
      expect(e.category, MemoryCategory.preference);
      expect(e.source, 'session:s1');
      final other = await s.save(
        'Schwester heißt Anna',
        category: MemoryCategory.person,
        source: 'session:s1',
      );
      expect(other.id, isNot(e.id));
      final listed = await s.list();
      expect(listed.map((x) => x.id), unorderedEquals([e.id, other.id]));
      expect(
        listed.singleWhere((x) => x.id == other.id).category,
        MemoryCategory.person,
      );
    },
    MemoryStoreChecks.listOrder: () async {
      final s = await create();
      final a = await fact(s, 'Erster Eintrag');
      final b = await fact(s, 'Zweiter Eintrag');
      final ids = (await s.list()).map((e) => e.id).toList();
      expect(ids.indexOf(b.id), lessThan(ids.indexOf(a.id)));
    },
    MemoryStoreChecks.search: () async {
      final s = await create();
      await fact(s, 'Wohnt in Hamburg');
      final k = await s.save(
        'Mag keinen Koriander',
        category: MemoryCategory.preference,
        source: 'contract',
      );
      for (var i = 0; i < 4; i++) {
        await fact(s, 'Koriander Notiz $i');
      }
      final found = await s.search('Koriander', limit: 3);
      expect(found, hasLength(3));
      expect(found.every((e) => e.text.contains('Koriander')), isTrue);
      final all = await s.search('Koriander', limit: 10);
      expect(all, hasLength(5));
      expect(all.map((e) => e.id), contains(k.id));
      expect(all.any((e) => e.text.contains('Hamburg')), isFalse);
      expect(await s.search('Zebrastreifen'), isEmpty);
    },
    MemoryStoreChecks.searchMarksUsed: () async {
      final s = await create();
      final e = await fact(s, 'Fährt gern Rad');
      expect(e.lastUsedAt, isNull);
      final hit = (await s.search('Rad')).single;
      expect(hit.lastUsedAt, isNotNull);
    },
    MemoryStoreChecks.forget: () async {
      final s = await create();
      final e = await s.save(
        'Projekt Wendelin',
        category: MemoryCategory.project,
        source: 'contract',
      );
      final keep = await fact(s, 'Projekt Garten');
      final removed = await s.forget(e.id);
      expect(removed.id, e.id);
      expect(removed.text, e.text);
      expect(removed.category, MemoryCategory.project);
      expect((await s.list()).map((x) => x.id), [keep.id]);
      expect((await s.search('Wendelin')).any((x) => x.id == e.id), isFalse);
      await expectLater(
        s.forget(e.id),
        throwsA(
          isA<PortException>().having(
            (p) => p.kind,
            'kind',
            PortErrorKind.notFound,
          ),
        ),
      );
    },
    MemoryStoreChecks.sensitive: () async {
      final s = await create();
      for (final text in [
        'Meine Karte: 4111 1111 1111 1111',
        'Konto DE89 3704 0044 0532 0130 00',
        'Mein Passwort ist geheim123',
        'PIN: 4711',
      ]) {
        await expectLater(
          fact(s, text),
          throwsA(
            isA<PortException>().having(
              (p) => p.kind,
              'kind',
              PortErrorKind.rejected,
            ),
          ),
          reason: text,
        );
      }
      expect(await s.list(), isEmpty);
    },
    MemoryStoreChecks.blank: () async {
      final s = await create();
      await expectLater(fact(s, '   '), throwsA(isA<ArgumentError>()));
      expect(await s.list(), isEmpty);
    },
  };
}
