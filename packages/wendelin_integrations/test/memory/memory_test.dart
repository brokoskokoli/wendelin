import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

void main() {
  late FakeMemoryStore store;
  late MemoryIntegration integration;
  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);

  setUp(() {
    store = FakeMemoryStore();
    integration = MemoryIntegration(store);
  });

  test('Integration: Metadaten', () async {
    expect(integration.id, 'memory');
    expect(integration.displayName, 'Gedächtnis');
    expect(integration.iconId, 'memory');
    expect(integration.sensitive, isTrue);
    expect(await integration.checkAvailability(), Availability.yes);
    expect(integration.setup, isEmpty);
    expect((await integration.setupState()).complete, isTrue);
    expect(integration.platforms, hasLength(2));
    expect(
      {for (final t in integration.tools) t.name: t.risk},
      {
        'memory__save': RiskLevel.write,
        'memory__search': RiskLevel.read,
        'memory__forget': RiskLevel.write,
      },
    );
  });

  test('Beschreibung von memory__save verlangt ausdrücklichen Wunsch', () {
    final d = tool('memory__save').description;
    expect(d, contains('ONLY'));
    expect(d, contains('explicitly'));
    expect(d, contains('passwords'));
  });

  group('memory__save', () {
    test('Erfolg mit Quelle aus der Sitzung; Undo vergisst', () async {
      final o = await tool('memory__save').execute({
        'text': 'Mag keinen Koriander',
        'category': 'preference',
      }, ctx());
      expect(o.isError, isFalse);
      final e = store.entries.single;
      expect(e.category, MemoryCategory.preference);
      expect(e.source, 'session:s1');
      expect(json(o), {
        'saved': {
          'id': 'm1',
          'text': 'Mag keinen Koriander',
          'category': 'preference',
        },
      });
      expect(o.summary, 'Gemerkt: Mag keinen Koriander');
      expect(o.undo!.label, 'Vergessen');
      await o.undo!();
      expect(store.entries, isEmpty);
    });

    for (final text in [
      'Meine Visa 4111-1111-1111-1111',
      'IBAN DE89370400440532013000',
      'Das WLAN-Passwort lautet Sommer2026',
      'Mein API-Key: abc123',
    ]) {
      test(
        'sensible Inhalte werden abgewiesen, bevor der Port sie sieht: $text',
        () async {
          final o = await tool('memory__save')
              .execute({'text': text, 'category': 'fact'}, ctx());
          expect(o.isError, isTrue);
          expect(o.text, contains('nicht gespeichert'));
          expect(store.methodCalls, isEmpty);
        },
      );
    }

    test(
      'Port wirft (eigene Schutzregel des Speichers) → Fehler-Outcome',
      () async {
        store.failNext(
          'save',
          const PortException(
            PortErrorKind.rejected,
            'Gesundheitsdaten werden nicht gespeichert.',
          ),
        );
        final o = await tool('memory__save')
            .execute({'text': 'Nimmt Medikament X', 'category': 'fact'}, ctx());
        expect(o.isError, isTrue);
        expect(o.text, 'Gesundheitsdaten werden nicht gespeichert.');
        expect(o.undo, isNull);
      },
    );

    for (final (label, args) in [
      ('Text fehlt', <String, Object?>{'category': 'fact'}),
      ('Kategorie fehlt', {'text': 'x'}),
      ('sensible Kategorie', {'text': 'x', 'category': 'health'}),
      (
        'Text zu lang',
        {'text': 'x' * (MemorySaveTool.maxChars + 1), 'category': 'fact'},
      ),
    ]) {
      test('ungültige Argumente: $label', () async {
        final o = await tool('memory__save').execute(args, ctx());
        expect(o.isError, isTrue);
        expect(o.text, startsWith('Ungültige Argumente'));
        expect(store.entries, isEmpty);
      });
    }

    test('Bestätigungstext', () {
      final t = tool('memory__save');
      expect(
        t.describeForConfirmation({
          'text': 'Wohnt in Hamburg',
          'category': 'fact',
        }),
        'Merken: Wohnt in Hamburg',
      );
      expect(t.describeForConfirmation({}), 'Etwas merken');
    });
  });

  group('memory__search', () {
    setUp(() async {
      await store.save(
        'Wohnt in Hamburg',
        category: MemoryCategory.fact,
        source: 't',
      );
      await store.save(
        'Mag Hamburg im Herbst',
        category: MemoryCategory.preference,
        source: 't',
      );
    });

    test('Erfolg', () async {
      final o = await tool('memory__search')
          .execute({'query': 'Hamburg', 'limit': 1}, ctx());
      expect(o.isError, isFalse);
      expect((json(o)['memories']! as List), hasLength(1));
      expect(o.summary, '1 Erinnerungen gefunden');
    });

    test('nichts gefunden', () async {
      final o = await tool('memory__search')
          .execute({'query': 'Berlin'}, ctx());
      expect(json(o), {'memories': <Object?>[]});
      expect(o.summary, 'Nichts gefunden');
    });

    test('Port-Fehler', () async {
      store.failNext('search');
      final o = await tool('memory__search')
          .execute({'query': 'Hamburg'}, ctx());
      expect(o.isError, isTrue);
    });

    test('ungültige Argumente', () async {
      for (final args in [
        <String, Object?>{},
        {'query': 'x', 'limit': 0},
        {'query': 'x', 'limit': 21},
      ]) {
        final o = await tool('memory__search').execute(args, ctx());
        expect(o.isError, isTrue, reason: '$args');
      }
    });

    test('Bestätigungstext', () {
      expect(
        tool('memory__search').describeForConfirmation({'query': 'Hamburg'}),
        'Gedächtnis durchsuchen: Hamburg',
      );
      expect(
        tool('memory__search').describeForConfirmation({}),
        'Gedächtnis durchsuchen',
      );
    });
  });

  group('memory__forget', () {
    test(
      'Erfolg; Undo speichert erneut mit gleicher Kategorie und Quelle',
      () async {
        final e = await store.save(
          'Projekt Garten',
          category: MemoryCategory.project,
          source: 'session:alt',
        );
        final o = await tool('memory__forget').execute({'id': e.id}, ctx());
        expect(o.isError, isFalse);
        expect(store.entries, isEmpty);
        expect(o.summary, 'Vergessen: Projekt Garten');
        expect(o.undo!.label, 'Wiederherstellen');
        await o.undo!();
        final back = store.entries.single;
        expect(back.text, 'Projekt Garten');
        expect(back.category, MemoryCategory.project);
        expect(back.source, 'session:alt');
        expect(back.id, isNot(e.id), reason: 'Undo vergibt eine neue Id');
      },
    );

    test('unbekannte Id', () async {
      final o = await tool('memory__forget').execute({'id': 'm99'}, ctx());
      expect(o.isError, isTrue);
      expect(o.text, contains('gibt es nicht'));
    });

    test('ungültige Argumente', () async {
      final o = await tool('memory__forget').execute({}, ctx());
      expect(o.isError, isTrue);
      expect(o.text, contains('„id“ fehlt'));
    });

    test('Bestätigungstext', () {
      expect(
        tool('memory__forget').describeForConfirmation({'id': 'm1'}),
        'Erinnerung m1 vergessen',
      );
      expect(
        tool('memory__forget').describeForConfirmation({}),
        'Erinnerung vergessen',
      );
    });
  });

  test('MemoryEntry: Gleichheit', () {
    final t = DateTime.utc(2026);
    final a = MemoryEntry(
      id: '1',
      text: 'x',
      category: MemoryCategory.fact,
      source: 's',
      createdAt: t,
    );
    expect(
      a,
      MemoryEntry(
        id: '1',
        text: 'x',
        category: MemoryCategory.fact,
        source: 's',
        createdAt: t,
      ),
    );
    expect(
      a.hashCode,
      MemoryEntry(
        id: '1',
        text: 'x',
        category: MemoryCategory.fact,
        source: 's',
        createdAt: t,
      ).hashCode,
    );
    expect(
      a,
      isNot(
        MemoryEntry(
          id: '1',
          text: 'x',
          category: MemoryCategory.person,
          source: 's',
          createdAt: t,
        ),
      ),
    );
    expect(a.toString(), contains('fact'));
  });
}
