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

  group('private runs (ADR 0009)', () {
    ToolContext at(PrivacyLevel? level, {PrivacyLevel? floor}) => ToolContext(
      sessionId: 's1',
      clock: FixedClock(DateTime.utc(2026, 10, 13, 12)),
      locale: 'de-DE',
      timeZone: 'Europe/Berlin',
      privacyLevel: level,
      privacyFloor: floor,
    );

    test('memory__save stores the floor of the run', () async {
      await tool('memory__save').execute({
        'text': 'Knie-OP im März',
        'category': 'fact',
      }, at(PrivacyLevel.tee, floor: PrivacyLevel.tee));
      expect(store.entries.single.privacyFloor, PrivacyLevel.tee);
      await tool('memory__save').execute({
        'text': 'Mag Tee',
        'category': 'preference',
      }, at(PrivacyLevel.standard));
      expect(store.entries.last.privacyFloor, isNull);
    });

    test('memory__search hides entries above the target level', () async {
      await store.save(
        'Knie-OP im März',
        category: MemoryCategory.fact,
        source: 's',
        privacyFloor: PrivacyLevel.tee,
      );
      await store.save(
        'Knie ist wieder gut',
        category: MemoryCategory.fact,
        source: 's',
      );
      Future<List<Object?>> found(PrivacyLevel? level) async =>
          json(
                await tool('memory__search')
                    .execute({'query': 'Knie'}, at(level)),
              )['memories']!
              as List<Object?>;
      expect(await found(PrivacyLevel.standard), hasLength(1));
      expect(await found(null), hasLength(1));
      expect(await found(PrivacyLevel.tee), hasLength(2));
      expect(await found(PrivacyLevel.local), hasLength(2));
    });

    test(
      'memory__forget treats hidden entries as unknown; undo keeps floor',
      () async {
        final e = await store.save(
          'Knie-OP im März',
          category: MemoryCategory.fact,
          source: 's',
          privacyFloor: PrivacyLevel.tee,
        );
        final weak = await tool('memory__forget')
            .execute({'id': e.id}, at(PrivacyLevel.standard));
        expect(weak.isError, isTrue);
        expect(weak.text, isNot(contains('Knie')));
        expect(store.entries, hasLength(1));
        final o = await tool('memory__forget')
            .execute({'id': e.id}, at(PrivacyLevel.tee));
        expect(store.entries, isEmpty);
        await o.undo!();
        expect(store.entries.single.privacyFloor, PrivacyLevel.tee);
      },
    );

    test('entry equality includes the floor', () {
      final t = DateTime.utc(2026);
      MemoryEntry e(PrivacyLevel? f) => MemoryEntry(
        id: '1',
        text: 'x',
        category: MemoryCategory.fact,
        source: 's',
        createdAt: t,
        privacyFloor: f,
      );
      expect(e(PrivacyLevel.tee), isNot(e(null)));
      expect(e(PrivacyLevel.tee).hashCode, e(PrivacyLevel.tee).hashCode);
      expect(e(PrivacyLevel.tee).visibleTo(PrivacyLevel.eu), isFalse);
    });
  });

  group('Namespace der Person (ToolContext.memoryOwner, WP92b)', () {
    ToolContext ctxOf(String owner) => ToolContext(
      sessionId: 's1',
      clock: FixedClock(DateTime.utc(2026, 10, 13, 12)),
      locale: 'de-DE',
      timeZone: 'Europe/Berlin',
      memoryOwner: owner,
    );

    Future<ToolOutcome> save(String text, String owner) =>
        tool('memory__save')
            .execute({'text': text, 'category': 'fact'}, ctxOf(owner));

    test('save, search und forget bleiben im Namespace', () async {
      final a = await save('Anna mag Koriander', 'p:a');
      await save('Ben mag Koriander', 'p:b');
      await save('Standard mag Koriander', '');
      expect(store.entriesOf('p:a'), hasLength(1));
      expect(store.entriesOf(''), hasLength(1));
      final found = json(
        await tool('memory__search')
            .execute({'query': 'Koriander'}, ctxOf('p:b')),
      );
      expect(
        (found['memories']! as List).single,
        containsPair('text', 'Ben mag Koriander'),
      );
      final id = (json(a)['saved']! as Map)['id']! as String;
      for (final other in ['', 'p:b']) {
        final o = await tool('memory__forget')
            .execute({'id': id}, ctxOf(other));
        expect(o.isError, isTrue);
      }
      expect(store.entriesOf('p:a'), hasLength(1));
    });

    test('Undo wirkt nur im Namespace des Aufrufs', () async {
      final o = await save('Anna mag Tee', 'p:a');
      expect(store.entriesOf('p:a'), hasLength(1));
      await o.undo!();
      expect(store.entriesOf('p:a'), isEmpty);

      await save('Ben mag Kaffee', 'p:b');
      final id = store.entriesOf('p:b').single.id;
      final f = await tool('memory__forget').execute({'id': id}, ctxOf('p:b'));
      expect(store.entriesOf('p:b'), isEmpty);
      await f.undo!(); // Wiederherstellen legt im selben Namespace an
      expect(store.entriesOf('p:b').single.text, 'Ben mag Kaffee');
      expect(store.entriesOf(''), isEmpty);
      expect(store.entriesOf('p:a'), isEmpty);
    });
  });
}
