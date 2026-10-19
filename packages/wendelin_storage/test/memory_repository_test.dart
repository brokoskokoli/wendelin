import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/src/db/memory_repository_impl.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/storage_fixture.dart';

void main() {
  late WendelinStorage storage;
  late FixedClock clock;
  late MemoryRepository repo;

  setUp(() {
    final f = openTestStorage();
    storage = f.storage;
    clock = f.clock;
    repo = storage.memory;
  });
  tearDown(() => storage.close());

  Future<StoredMemory> save(
    String text, [
    StoredMemoryCategory category = StoredMemoryCategory.fact,
  ]) {
    clock.advance(const Duration(minutes: 1));
    return repo.save(text, category: category, source: 'user');
  }

  group('save, get, list, update, forget', () {
    test('clearPrivacyFloor entfernt nur die Untergrenze', () async {
      final e = await repo.save(
        'Diagnose X',
        category: StoredMemoryCategory.fact,
        source: 'user',
        privacyFloor: PrivacyLevel.tee,
      );
      expect(e.privacyFloor, PrivacyLevel.tee);
      final cleared = await repo.clearPrivacyFloor(e.id);
      expect(cleared!.privacyFloor, isNull);
      expect(cleared.text, 'Diagnose X');
      expect((await repo.get(e.id))!.privacyFloor, isNull);
      expect(await repo.clearPrivacyFloor('fehlt'), isNull);
    });

    test('save setzt Zeiten aus der Uhr', () async {
      final e = await save(
        'Anna ist meine Schwester',
        StoredMemoryCategory.person,
      );
      expect(e.createdAt, clock.now());
      expect(e.lastUsedAt, clock.now());
      expect(e.source, 'user');
      expect(await repo.get(e.id), e);
      expect(await repo.get('fehlt'), isNull);
    });

    test('list: neueste zuerst, optional nach Kategorie', () async {
      final a = await save('a', StoredMemoryCategory.person);
      final b = await save('b', StoredMemoryCategory.preference);
      final c = await save('c', StoredMemoryCategory.person);
      expect(await repo.list(), [c, b, a]);
      expect(await repo.list(category: StoredMemoryCategory.person), [c, a]);
      expect(await repo.list(category: StoredMemoryCategory.project), isEmpty);
    });

    test(
      'update ändert Text und Kategorie, Suche folgt dem neuen Text',
      () async {
        final e = await save('Ich mag Kaffee', StoredMemoryCategory.preference);
        final u = await repo.update(e.id, text: 'Ich mag Tee');
        expect(u!.text, 'Ich mag Tee');
        expect(u.category, StoredMemoryCategory.preference);
        expect(u.createdAt, e.createdAt);
        expect(await repo.search('Kaffee'), isEmpty);
        expect((await repo.search('Tee')).single.id, e.id);
        final v = await repo.update(e.id, category: StoredMemoryCategory.fact);
        expect(v!.text, 'Ich mag Tee');
        expect(v.category, StoredMemoryCategory.fact);
        expect(await repo.update('fehlt', text: 'x'), isNull);
      },
    );

    test('forget entfernt Eintrag und Suchindex', () async {
      final e = await save('Tauchen in Tulamben');
      expect(await repo.forget(e.id), isTrue);
      expect(await repo.forget(e.id), isFalse);
      expect(await repo.get(e.id), isNull);
      expect(await repo.search('Tulamben'), isEmpty);
    });
  });

  group('Schutzregel', () {
    test('save lehnt Kartennummer, IBAN und Passwort ab', () async {
      for (final text in [
        'Meine Visa ist 4111 1111 1111 1111',
        'Konto DE89 3704 0044 0532 0130 00',
        'Passwort: hund123',
        'Die PIN ist 4711',
      ]) {
        await expectLater(
          repo.save(text, category: StoredMemoryCategory.fact, source: 'user'),
          throwsA(isA<SensitiveContentException>()),
          reason: text,
        );
      }
      expect(await repo.list(), isEmpty);
    });

    test(
      'update lehnt sensible Texte ab und lässt den Eintrag unverändert',
      () async {
        final e = await save('harmlos');
        await expectLater(
          repo.update(e.id, text: 'Kennwort = geheim'),
          throwsA(
            isA<SensitiveContentException>().having(
              (x) => x.kind,
              'kind',
              SensitiveKind.credential,
            ),
          ),
        );
        expect((await repo.get(e.id))!.text, 'harmlos');
      },
    );
  });

  group('search (FTS5, bm25)', () {
    late Map<String, StoredMemory> e;

    setUp(() async {
      e = {
        'tauchenBali': await save(
          'Ich tauche gern in Bali, am liebsten Tulamben',
        ),
        'tauchenOft': await save(
          'Tauchen Tauchen Tauchen: Tauchen ist mein Hobby, Tauchen am Wochenende',
        ),
        'anna': await save(
          'Anna ist meine Schwester',
          StoredMemoryCategory.person,
        ),
        'kaffee': await save(
          'Ich trinke Kaffee schwarz',
          StoredMemoryCategory.preference,
        ),
        'projekt': await save(
          'Projekt Wendelin: Sprachassistent',
          StoredMemoryCategory.project,
        ),
        'zahnarzt': await save('Zahnarzt heißt Dr. Müller'),
        'auto': await save('Mein Auto ist ein blauer Kombi'),
        'muenchen': await save('Ich wohne in München'),
        'geburtstag': await save(
          'Annas Geburtstag ist am 3. Mai',
          StoredMemoryCategory.person,
        ),
        'tauchschein': await save('Tauchschein: Advanced Open Water'),
        'sport': await save('Laufen am Dienstag'),
        'kaffeeMaschine': await save(
          'Die Kaffeemaschine entkalken alle 4 Wochen',
        ),
      };
    });

    test('relevantester Eintrag zuerst, nur passende Einträge', () async {
      final r = await repo.search('tauch');
      expect(r.first.id, e['tauchenOft']!.id);
      expect(r.map((x) => x.id).toSet(), {
        e['tauchenOft']!.id,
        e['tauchenBali']!.id,
        e['tauchschein']!.id,
      });
    });

    test(
      'mehrere Wörter: Eintrag mit beiden Wörtern vor Einträgen mit einem',
      () async {
        final r = await repo.search('Kaffee schwarz');
        expect(r.first.id, e['kaffee']!.id);
        expect([for (final x in r) x.id], contains(e['kaffeeMaschine']!.id));
      },
    );

    test('Präfix und Umlaut-/Groß-Kleinschreibung-unabhängig', () async {
      expect((await repo.search('MUNCHEN')).single.id, e['muenchen']!.id);
      expect((await repo.search('Anna')).map((x) => x.id).toSet(), {
        e['anna']!.id,
        e['geburtstag']!.id,
      });
    });

    test('limit begrenzt, Standard 5', () async {
      const many = 'Tauchen Anna Kaffee Auto München Projekt Laufen';
      expect(await repo.search(many, limit: 2), hasLength(2));
      expect(await repo.search(many), hasLength(5));
      expect(await repo.search('Anna', limit: 0), isEmpty);
    });

    test(
      'FTS-Syntax im Text ist wirkungslos, leere Anfrage liefert nichts',
      () async {
        expect(await repo.search('"'), isEmpty);
        expect(await repo.search('   '), isEmpty);
        expect(await repo.search('Anna AND NOT OR (*'), isNotEmpty);
        expect(await repo.search('body:Anna'), isNotEmpty);
      },
    );

    test('Treffer bekommen lastUsedAt = jetzt, andere nicht', () async {
      clock.advance(const Duration(days: 1));
      final r = await repo.search('Schwester');
      expect(r.single.lastUsedAt, clock.now());
      expect((await repo.get(e['anna']!.id))!.lastUsedAt, clock.now());
      expect(
        (await repo.get(e['auto']!.id))!.lastUsedAt,
        e['auto']!.lastUsedAt,
      );
    });
  });

  test('ftsQuery quotet Wörter als Präfix-Terme', () {
    expect(ftsQuery('Anna "Bali" NOT'), '"Anna"* OR "Bali"* OR "NOT"*');
    expect(ftsQuery('?!'), isNull);
  });

  test('ftsQuery lässt Ein-Zeichen-Wörter und Stoppwörter weg', () {
    expect(ftsQuery('Was ist mit Anna?'), '"Anna"*');
    expect(ftsQuery('what is my car'), '"car"*');
    expect(ftsQuery('Qui est le médecin'), '"médecin"*');
    expect(ftsQuery('a b 3 Xy'), '"Xy"*');
    expect(ftsQuery('Der die das'), isNull);
  });

  test('Suche nur aus Stoppwörtern liefert nichts', () async {
    await save('Ich bin in München');
    expect(await repo.search('ich bin in'), isEmpty);
    expect(await repo.search('Wo bin ich in München?'), hasLength(1));
  });

  test('exportMarkdown gruppiert nach Kategorie', () async {
    expect(await repo.exportMarkdown(), '# Gedächtnis\n');
    await save('Ich mag Tee', StoredMemoryCategory.preference);
    await save('Anna ist meine\nSchwester', StoredMemoryCategory.person);
    await save('Bernd ist mein Nachbar', StoredMemoryCategory.person);
    expect(
      await repo.exportMarkdown(),
      '# Gedächtnis\n'
      '\n## Personen\n\n'
      '- Anna ist meine Schwester (user, 2026-10-13)\n'
      '- Bernd ist mein Nachbar (user, 2026-10-13)\n'
      '\n## Vorlieben\n\n'
      '- Ich mag Tee (user, 2026-10-13)\n',
    );
  });

  group('Namespaces (WP92b)', () {
    Future<StoredMemory> saveFor(String owner, String text) => repo.save(
      text,
      category: StoredMemoryCategory.fact,
      source: 'user',
      owner: owner,
    );

    test(
      'list, search, count und Export sehen nur den eigenen Namespace',
      () async {
        final std = await saveFor('', 'Standard mag Koriander');
        final a = await saveFor('p:a', 'Anna mag Koriander');
        final b = await saveFor('p:b', 'Ben mag Koriander');
        expect((await repo.list()).map((e) => e.id), [std.id]);
        expect((await repo.list(owner: 'p:a')).map((e) => e.id), [a.id]);
        expect((await repo.search('Koriander')).map((e) => e.id), [std.id]);
        expect(
          (await repo.search('Koriander', owner: 'p:b')).map((e) => e.id),
          [b.id],
        );
        expect(await repo.search('Koriander', owner: 'p:zzz'), isEmpty);
        expect(await repo.count(), 1);
        expect(await repo.count(owner: 'p:a'), 1);
        final md = await repo.exportMarkdown(owner: 'p:a');
        expect(md, contains('Anna'));
        expect(md, isNot(contains('Ben')));
        expect(md, isNot(contains('Standard')));
        expect(md, isNot(contains('p:a')));
        expect(await repo.exportMarkdown(), isNot(contains('Anna')));
      },
    );

    test(
      'get, update, clearPrivacyFloor und forget treffen keine fremde Id',
      () async {
        final a = await repo.save(
          'Anna Befund',
          category: StoredMemoryCategory.fact,
          source: 'user',
          privacyFloor: PrivacyLevel.tee,
          owner: 'p:a',
        );
        for (final other in ['', 'p:b']) {
          expect(await repo.get(a.id, owner: other), isNull);
          expect(await repo.update(a.id, text: 'x', owner: other), isNull);
          expect(await repo.clearPrivacyFloor(a.id, owner: other), isNull);
          expect(await repo.forget(a.id, owner: other), isFalse);
        }
        final kept = (await repo.get(a.id, owner: 'p:a'))!;
        expect(kept.text, 'Anna Befund');
        expect(kept.privacyFloor, PrivacyLevel.tee);
        expect(await repo.forget(a.id, owner: 'p:a'), isTrue);
      },
    );

    test(
      'deleteOwner löscht nur den Namespace, nie das Standard-Gedächtnis',
      () async {
        await saveFor('', 'Standard');
        await saveFor('p:a', 'Anna eins');
        await saveFor('p:a', 'Anna zwei');
        final b = await saveFor('p:b', 'Ben');
        expect(await repo.deleteOwner(''), 0);
        expect(await repo.count(), 1);
        expect(await repo.deleteOwner('p:a'), 2);
        expect(await repo.count(owner: 'p:a'), 0);
        expect(await repo.search('Anna', owner: 'p:a'), isEmpty);
        expect(await repo.count(), 1);
        expect((await repo.get(b.id, owner: 'p:b'))!.text, 'Ben');
      },
    );
  });
}
