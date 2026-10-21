import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

const _einkaufen =
    '---\r\ntags: [liste]\r\n---\r\n'
    '# Einkaufen\r\n'
    'Für den Wochenmarkt.\r\n'
    '- [ ] Milch (1 l)\r\n'
    '- [x] Brot\r\n'
    '- [ ] Äpfel\r\n'
    '\r\n'
    'Notizen am Ende ohne Umbruch';

const _projekt =
    '# SmartSSH\n'
    '## Todo\n'
    '- [ ] Release bauen\n'
    '  - [ ] Changelog\n'
    '  - [x] Version setzen\n'
    '- [x] Tests\n'
    '  - [x] Unit\n'
    '- [x] Doku\n'
    '  - [ ] Bilder\n'
    '\n'
    '## Ideen\n'
    '- [ ] Dark Mode\n';

void main() {
  late FakeListFilePort port;
  late List<ListDefinition> defs;
  late ListsIntegration integration;

  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);
  Future<ToolOutcome> run(String name, Map<String, Object?> args) =>
      tool(name).execute(args, ctx());
  Map<String, Object?> data(ToolOutcome o) => jsonDecode(
    o.text.startsWith(listDataNotice)
        ? o.text.substring(listDataNotice.length)
        : o.text,
  ) as Map<String, Object?>;

  setUp(() {
    port = FakeListFilePort(
      files: {'einkaufen.md': _einkaufen, 'projekt.md': _projekt},
    );
    defs = [
      ListDefinition(
        id: 'e',
        name: 'Einkaufen',
        target: 'einkaufen.md',
        aliases: ['Einkaufsliste', 'shopping'],
      ),
      ListDefinition(
        id: 's',
        name: 'SmartSSH',
        target: 'projekt.md',
        section: 'Todo',
      ),
      ListDefinition(id: 'n', name: 'Neu', target: 'neu.md'),
      ListDefinition(id: 'u1', name: 'Urlaub Packliste', target: 'u1.md'),
      ListDefinition(id: 'u2', name: 'Urlaub Ideen', target: 'u2.md'),
    ];
    integration = ListsIntegration(port, definitions: () => defs);
  });

  group('Integration', () {
    test('Metadaten', () async {
      expect(integration.id, 'lists');
      expect(integration.displayName, 'Listen');
      expect(integration.iconId, 'list');
      expect(integration.sensitive, isFalse);
      expect(integration.platforms, hasLength(2));
      expect(await integration.checkAvailability(), Availability.yes);
      expect((await integration.setupState()).complete, isTrue);
      defs = [];
      expect((await integration.setupState()).missingSteps, [
        ListsIntegration.defineStep,
      ]);
      expect(
        {for (final t in integration.tools) t.name: t.risk},
        {
          'lists__list_lists': RiskLevel.read,
          'lists__get_items': RiskLevel.read,
          'lists__add_items': RiskLevel.write,
          'lists__complete_item': RiskLevel.write,
          'lists__remove_item': RiskLevel.write,
          'lists__clear_completed': RiskLevel.external,
        },
      );
    });

    test('ListDefinition: Gleichheit', () {
      final a = ListDefinition(id: '1', name: 'A', target: 't', aliases: ['x']);
      expect(
        a,
        ListDefinition(id: '1', name: 'A', target: 't', aliases: ['x']),
      );
      expect(
        a.hashCode,
        ListDefinition(
          id: '1',
          name: 'A',
          target: 't',
          aliases: ['x'],
        ).hashCode,
      );
      expect(a, isNot(ListDefinition(id: '1', name: 'A', target: 't')));
      expect(a.toString(), contains('A'));
    });
  });

  group('lists__list_lists', () {
    test(
      'Namen und offene Einträge; fehlende Datei = 0; Fehler je Liste',
      () async {
        port.files['u1.md'] = '- [ ] Zelt\n';
        port.failNext(
          'exists',
          const PortException(PortErrorKind.permissionDenied, 'Kein Zugriff'),
        );
        final o = await run('lists__list_lists', {});
        expect(o.isError, isFalse);
        expect(data(o)['lists'], [
          {'name': 'Einkaufen', 'error': 'Kein Zugriff'},
          {'name': 'SmartSSH', 'open': 3},
          {'name': 'Neu', 'open': 0, 'missing_file': true},
          {'name': 'Urlaub Packliste', 'open': 1},
          {'name': 'Urlaub Ideen', 'open': 0, 'missing_file': true},
        ]);
        expect(o.summary, '5 Listen');
        expect(
          tool('lists__list_lists').describeForConfirmation({}),
          'Listen anzeigen',
        );
      },
    );
  });

  group('lists__get_items', () {
    test('offene Einträge als Daten markiert', () async {
      final o = await run('lists__get_items', {'list': 'Einkaufsliste'});
      expect(o.isError, isFalse);
      expect(o.text, startsWith(listDataNotice));
      expect(data(o), {
        'list': 'Einkaufen',
        'items': [
          {'text': 'Milch (1 l)'},
          {'text': 'Äpfel'},
        ],
        'done_hidden': 1,
      });
      expect(o.summary, 'Einkaufen: 2 offen');
    });

    test('include_done und Abschnitt', () async {
      final o = await run('lists__get_items', {
        'list': 'smart ssh',
        'include_done': true,
      });
      expect(
        [for (final i in data(o)['items']! as List) (i as Map)['text']],
        [
          'Release bauen',
          'Changelog',
          'Version setzen',
          'Tests',
          'Unit',
          'Doku',
          'Bilder',
        ],
      );
      expect(o.text, isNot(contains('Dark Mode')));
    });

    test('fehlende Datei: leere Liste; fehlender Abschnitt: leer', () async {
      expect(
        data(await run('lists__get_items', {'list': 'Neu'}))['items'],
        isEmpty,
      );
      port.files['projekt.md'] = '# Nur Titel\n';
      expect(
        data(await run('lists__get_items', {'list': 'SmartSSH'}))['items'],
        isEmpty,
      );
    });

    test('mehrdeutige Liste: Fehler mit Kandidaten', () async {
      final o = await run('lists__get_items', {'list': 'Urlaub'});
      expect(o.isError, isTrue);
      expect(o.text, contains('Urlaub Packliste'));
      expect(o.text, contains('Urlaub Ideen'));
      expect(o.text, contains('nachfragen'));
    });

    test('unbekannte Liste, Port-Fehler, ungültige Argumente', () async {
      expect(
        (await run('lists__get_items', {'list': 'Weihnachten'})).text,
        contains('Keine Liste'),
      );
      port.failNext('read');
      expect(
        (await run('lists__get_items', {'list': 'Einkaufen'})).isError,
        isTrue,
      );
      final bad = await run('lists__get_items', {});
      expect(bad.text, startsWith('Ungültige Argumente'));
    });

    test('Bestätigungstext', () {
      expect(
        tool('lists__get_items').describeForConfirmation({'list': 'X'}),
        'Liste X anzeigen',
      );
      expect(
        tool('lists__get_items').describeForConfirmation({}),
        'Liste anzeigen',
      );
    });
  });

  group('lists__add_items', () {
    test(
      '„Füge Milch und Eier zur Einkaufsliste hinzu“: Rest zeichengenau',
      () async {
        final o = await run('lists__add_items', {
          'list': 'Einkaufsliste',
          'items': ['milch (1 L)', 'Eier', 'Butter', 'eier'],
        });
        expect(o.isError, isFalse);
        expect(
          port.files['einkaufen.md'],
          _einkaufen.replaceFirst(
            '- [ ] Äpfel\r\n',
            '- [ ] Äpfel\r\n- [ ] Eier\r\n- [ ] Butter\r\n',
          ),
        );
        expect(data(o), {
          'list': 'Einkaufen',
          'added': ['Eier', 'Butter'],
          'already_present': ['milch (1 L)', 'eier'],
        });
        expect(o.summary, 'Einkaufen: Eier, Butter hinzugefügt');
      },
    );

    test('erledigter Eintrag gleichen Namens wird neu angelegt', () async {
      await run('lists__add_items', {
        'list': 'Einkaufen',
        'items': ['Brot'],
      });
      expect(
        port.files['einkaufen.md'],
        contains('- [ ] Äpfel\r\n- [ ] Brot\r\n'),
      );
    });

    test('alles schon vorhanden: kein Schreiben, kein Undo', () async {
      final o = await run('lists__add_items', {
        'list': 'Einkaufen',
        'items': ['Äpfel'],
      });
      expect(o.isError, isFalse);
      expect(o.undo, isNull);
      expect(port.writes, 0);
      expect(o.summary, 'Einkaufen: schon vorhanden');
    });

    test('Undo entfernt genau die hinzugefügten Zeilen, auch nach fremder Änderung', () async {
      final o = await run('lists__add_items', {
        'list': 'Einkaufen',
        'items': ['Eier', 'Käse'],
      });
      // Obsidian Sync schreibt dazwischen: neue Zeile oben, ein Eintrag mehr.
      port.files['einkaufen.md'] = port.files['einkaufen.md']!
          .replaceFirst('# Einkaufen\r\n', '# Einkaufen\r\nNeu oben\r\n')
          .replaceFirst('- [ ] Käse\r\n', '- [ ] Käse\r\n- [ ] Senf\r\n');
      await o.undo!();
      expect(
        port.files['einkaufen.md'],
        _einkaufen
            .replaceFirst('# Einkaufen\r\n', '# Einkaufen\r\nNeu oben\r\n')
            .replaceFirst('- [ ] Äpfel\r\n', '- [ ] Äpfel\r\n- [ ] Senf\r\n'),
      );
    });

    test(
      'Undo, wenn die Zeilen inzwischen weg sind: Fehler, nichts geschrieben',
      () async {
        final o = await run('lists__add_items', {
          'list': 'Einkaufen',
          'items': ['Eier'],
        });
        port.files['einkaufen.md'] = _einkaufen;
        final writes = port.writes;
        await expectLater(o.undo!(), throwsA(isA<PortException>()));
        expect(port.writes, writes);
      },
    );

    test('neue Datei wird angelegt; Undo hinterlässt leere Datei', () async {
      final o = await run('lists__add_items', {
        'list': 'Neu',
        'items': ['Erstes'],
      });
      expect(port.files['neu.md'], '- [ ] Erstes\n');
      await o.undo!();
      expect(port.files['neu.md'], '');
    });

    test(
      'fehlender Abschnitt wird angelegt; Undo entfernt ihn wieder',
      () async {
        port.files['projekt.md'] = '# SmartSSH\nText';
        final o = await run('lists__add_items', {
          'list': 'SmartSSH',
          'items': ['A'],
        });
        expect(
          port.files['projekt.md'],
          '# SmartSSH\nText\n\n## Todo\n- [ ] A',
        );
        await o.undo!();
        expect(port.files['projekt.md'], '# SmartSSH\nText');
      },
    );

    test(
      'Abschnitt: Eintrag nach dem ersten Block inkl. Unterpunkte',
      () async {
        await run('lists__add_items', {
          'list': 'SmartSSH',
          'items': ['Store-Text'],
        });
        expect(
          port.files['projekt.md'],
          _projekt.replaceFirst(
            '  - [ ] Bilder\n',
            '  - [ ] Bilder\n- [ ] Store-Text\n',
          ),
        );
      },
    );

    test(
      'liest vor dem Schreiben neu (fremde Änderung bleibt erhalten)',
      () async {
        await run('lists__get_items', {'list': 'Einkaufen'});
        port.files['einkaufen.md'] = '- [ ] Fremd\n';
        await run('lists__add_items', {
          'list': 'Einkaufen',
          'items': ['Eier'],
        });
        expect(port.files['einkaufen.md'], '- [ ] Fremd\n- [ ] Eier\n');
      },
    );

    test('Schreibfehler des Ports', () async {
      port.readOnly.add('einkaufen.md');
      final o = await run('lists__add_items', {
        'list': 'Einkaufen',
        'items': ['Eier'],
      });
      expect(o.isError, isTrue);
      expect(o.text, contains('Schreibzugriff'));
      expect(port.files['einkaufen.md'], _einkaufen);
    });

    for (final (label, args) in [
      ('items fehlt', <String, Object?>{'list': 'Einkaufen'}),
      ('items leer', {'list': 'Einkaufen', 'items': <String>[]}),
      (
        'leerer Eintrag',
        {
          'list': 'Einkaufen',
          'items': ['  '],
        },
      ),
      (
        'Zeilenumbruch',
        {
          'list': 'Einkaufen',
          'items': ['a\n- [x] b'],
        },
      ),
      ('kein Array', {'list': 'Einkaufen', 'items': 'Milch'}),
      ('zu viele', {'list': 'Einkaufen', 'items': List.filled(51, 'x')}),
      (
        'Liste fehlt',
        {
          'items': ['x'],
        },
      ),
    ]) {
      test('ungültige Argumente: $label', () async {
        final o = await run('lists__add_items', args);
        expect(o.isError, isTrue);
        expect(port.writes, 0);
      });
    }

    test('Bestätigungstext', () {
      final t = tool('lists__add_items');
      expect(
        t.describeForConfirmation({
          'list': 'Einkaufen',
          'items': ['Milch', 'Eier'],
        }),
        'Milch, Eier zur Liste Einkaufen hinzufügen',
      );
      expect(t.describeForConfirmation({}), 'Zur Liste hinzufügen');
    });
  });

  group('lists__complete_item', () {
    test('unscharfer Treffer; nur das Kästchen ändert sich; Undo', () async {
      final o = await run('lists__complete_item', {
        'list': 'Einkaufen',
        'item': 'milch (1 L)',
      });
      expect(o.isError, isFalse);
      expect(
        port.files['einkaufen.md'],
        _einkaufen.replaceFirst('- [ ] Milch', '- [x] Milch'),
      );
      expect(o.summary, 'Einkaufen: Milch (1 l) erledigt');
      await o.undo!();
      expect(port.files['einkaufen.md'], _einkaufen);
    });

    test('Undo nach fremder Änderung trifft dieselbe Zeile', () async {
      final o = await run('lists__complete_item', {
        'list': 'Einkaufen',
        'item': 'Äpfel',
      });
      port.files['einkaufen.md'] = 'Oben neu\r\n${port.files['einkaufen.md']!}';
      await o.undo!();
      expect(port.files['einkaufen.md'], 'Oben neu\r\n$_einkaufen');
    });

    test('Undo, wenn die Zeile geändert wurde: Fehler', () async {
      final o = await run('lists__complete_item', {
        'list': 'Einkaufen',
        'item': 'Äpfel',
      });
      port.files['einkaufen.md'] = _einkaufen.replaceFirst('Äpfel', 'Birnen');
      await expectLater(o.undo!(), throwsA(isA<PortException>()));
    });

    test('schon erledigt: Hinweis statt Fehler', () async {
      final o = await run('lists__complete_item', {
        'list': 'Einkaufen',
        'item': 'Brot',
      });
      expect(o.isError, isFalse);
      expect(data(o)['already_done'], 'Brot');
      expect(o.undo, isNull);
      expect(port.writes, 0);
    });

    test('nicht vorhanden und mehrdeutig', () async {
      final none = await run('lists__complete_item', {
        'list': 'Einkaufen',
        'item': 'Kaviar',
      });
      expect(none.isError, isTrue);
      expect(none.text, contains('steht nicht'));
      port.files['einkaufen.md'] = '- [ ] Milch hell\n- [ ] Milch dunkel\n';
      final two = await run('lists__complete_item', {
        'list': 'Einkaufen',
        'item': 'Milch',
      });
      expect(two.isError, isTrue);
      expect(two.text, allOf(contains('Milch hell'), contains('Milch dunkel')));
    });

    test('ungültige Argumente und Bestätigungstext', () async {
      expect(
        (await run('lists__complete_item', {'list': 'Einkaufen'})).isError,
        isTrue,
      );
      expect(
        tool('lists__complete_item')
            .describeForConfirmation({'list': 'Einkaufen', 'item': 'Milch'}),
        'Milch auf Einkaufen abhaken',
      );
      expect(
        tool('lists__complete_item').describeForConfirmation({}),
        'Eintrag abhaken',
      );
    });
  });

  group('lists__remove_item', () {
    test('entfernt samt Unterpunkten; Undo an derselben Stelle nach fremder Änderung', () async {
      final o = await run('lists__remove_item', {
        'list': 'SmartSSH',
        'item': 'release bauen',
      });
      expect(o.isError, isFalse);
      expect(
        port.files['projekt.md'],
        _projekt.replaceFirst(
          '- [ ] Release bauen\n  - [ ] Changelog\n  - [x] Version setzen\n',
          '',
        ),
      );
      port.files['projekt.md'] = 'Kopf\n${port.files['projekt.md']!}';
      await o.undo!();
      expect(port.files['projekt.md'], 'Kopf\n$_projekt');
    });

    test(
      'letzte Zeile ohne Umbruch: Entfernen und Undo zeichengenau',
      () async {
        port.files['einkaufen.md'] = '- [ ] A\r\n- [ ] B';
        final o = await run('lists__remove_item', {
          'list': 'Einkaufen',
          'item': 'B',
        });
        expect(port.files['einkaufen.md'], '- [ ] A');
        await o.undo!();
        expect(port.files['einkaufen.md'], '- [ ] A\r\n- [ ] B');
      },
    );

    test('erste Zeile: Undo fügt am Anfang ein', () async {
      port.files['einkaufen.md'] = '- [ ] A\n- [ ] B\n';
      final o = await run('lists__remove_item', {
        'list': 'Einkaufen',
        'item': 'A',
      });
      await o.undo!();
      expect(port.files['einkaufen.md'], '- [ ] A\n- [ ] B\n');
    });

    test('Ankerzeile verschwunden: Einfügen an alter Position', () async {
      port.files['einkaufen.md'] = 'x\n- [ ] A\n- [ ] B\n';
      final o = await run('lists__remove_item', {
        'list': 'Einkaufen',
        'item': 'B',
      });
      port.files['einkaufen.md'] = 'y\n- [ ] A\n';
      await o.undo!();
      expect(port.files['einkaufen.md'], 'y\n- [ ] A\n- [ ] B\n');
    });

    test('offener Eintrag hat Vorrang, erledigter ist auch löschbar', () async {
      port.files['einkaufen.md'] = '- [x] Milch\n- [ ] Milch\n- [x] Brot\n';
      await run('lists__remove_item', {'list': 'Einkaufen', 'item': 'Milch'});
      expect(port.files['einkaufen.md'], '- [x] Milch\n- [x] Brot\n');
      await run('lists__remove_item', {'list': 'Einkaufen', 'item': 'Brot'});
      expect(port.files['einkaufen.md'], '- [x] Milch\n');
    });

    test('nicht vorhanden; Bestätigungstext', () async {
      final o = await run('lists__remove_item', {
        'list': 'Einkaufen',
        'item': 'Kaviar',
      });
      expect(o.isError, isTrue);
      expect(
        tool('lists__remove_item')
            .describeForConfirmation({'list': 'Einkaufen', 'item': 'Eier'}),
        'Eier von Einkaufen entfernen',
      );
      expect(
        tool('lists__remove_item').describeForConfirmation({}),
        'Eintrag entfernen',
      );
    });
  });

  group('lists__clear_completed', () {
    test('löscht Erledigte samt Unterpunkten, behält solche mit offenen Unteraufgaben', () async {
      final o = await run('lists__clear_completed', {'list': 'SmartSSH'});
      expect(o.isError, isFalse);
      expect(
        port.files['projekt.md'],
        '# SmartSSH\n'
        '## Todo\n'
        '- [ ] Release bauen\n'
        '  - [ ] Changelog\n'
        '- [x] Doku\n'
        '  - [ ] Bilder\n'
        '\n'
        '## Ideen\n'
        '- [ ] Dark Mode\n',
      );
      expect(data(o), {
        'list': 'SmartSSH',
        'removed': 3,
        'kept': ['Doku'],
      });
    });

    test(
      'Rest der Datei zeichengenau; nichts zu tun = kein Schreiben',
      () async {
        await run('lists__clear_completed', {'list': 'Einkaufen'});
        expect(
          port.files['einkaufen.md'],
          _einkaufen.replaceFirst('- [x] Brot\r\n', ''),
        );
        final writes = port.writes;
        await run('lists__clear_completed', {'list': 'Einkaufen'});
        expect(port.writes, writes);
      },
    );

    test('Bestätigungstext', () {
      expect(
        tool('lists__clear_completed')
            .describeForConfirmation({'list': 'Einkaufen'}),
        'Erledigte Einträge von Einkaufen löschen',
      );
      expect(
        tool('lists__clear_completed').describeForConfirmation({}),
        'Erledigte Einträge löschen',
      );
    });
  });

  test('„Was steht auf der Liste SmartSSH?“', () async {
    final o = await run('lists__get_items', {'list': 'Liste SmartSSH'});
    expect(
      [for (final i in data(o)['items']! as List) (i as Map)['text']],
      ['Release bauen', 'Changelog', 'Bilder'],
    );
  });

  group('feste Bestätigung', () {
    test('add_items: Vollerfolg (Plural, Singular)', () async {
      final t = tool('lists__add_items');
      expectFixed(
        await run('lists__add_items', {
          'list': 'Einkaufen',
          'items': ['Eier', 'Butter'],
        }),
        t,
        'list.added',
        de: 'Eier und Butter stehen jetzt auf der Liste Einkaufen.',
      );
      expectFixed(
        await run('lists__add_items', {
          'list': 'Einkaufen',
          'items': ['Käse'],
        }),
        t,
        'list.added',
        de: 'Käse steht jetzt auf der Liste Einkaufen.',
      );
    });

    test('add_items: Duplikate übersprungen → Modell formuliert', () async {
      final o = await run('lists__add_items', {
        'list': 'Einkaufen',
        'items': ['Eier', 'milch (1 L)'],
      });
      expect(o.isError, isFalse);
      expect(o.fixed, isNull);
    });

    test('add_items: unbekannte Liste → Fehler ohne Satz', () async {
      final o = await run('lists__add_items', {
        'list': 'Gibtsnicht',
        'items': ['Eier'],
      });
      expect(o.isError, isTrue);
      expect(o.fixed, isNull);
    });

    test('complete_item: abgehakt', () async {
      expectFixed(
        await run('lists__complete_item', {
          'list': 'Einkaufen',
          'item': 'milch (1 L)',
        }),
        tool('lists__complete_item'),
        'list.done',
        de: 'Milch (1 l) ist auf der Liste Einkaufen abgehakt.',
      );
    });

    test('complete_item: schon erledigt → kein Satz', () async {
      final o = await run('lists__complete_item', {
        'list': 'Einkaufen',
        'item': 'Brot',
      });
      expect(o.isError, isFalse);
      expect(o.fixed, isNull);
    });
  });
}
