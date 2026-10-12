// Regressionstests zu den Review-Befunden WP12.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/src/lists/markdown_list.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

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
    port = FakeListFilePort(files: {'e.md': '- [ ] Brot\n'});
    defs = [
      ListDefinition(id: 'e', name: 'Einkaufen', target: 'e.md'),
      ListDefinition(id: 'p', name: 'Projekt', target: 'p.md', section: 'Todo'),
    ];
    integration = ListsIntegration(port, definitions: () => defs);
  });

  group('1: parallele Tool-Calls auf dieselbe Datei', () {
    setUp(() => port.delay = const Duration(milliseconds: 2));

    test('add + complete gleichzeitig: keine Änderung geht verloren', () async {
      final results = await Future.wait([
        run('lists__add_items', {
          'list': 'Einkaufen',
          'items': ['Milch'],
        }),
        run('lists__complete_item', {'list': 'Einkaufen', 'item': 'Brot'}),
      ]);
      expect(results.every((o) => !o.isError), isTrue);
      expect(port.files['e.md'], '- [x] Brot\n- [ ] Milch\n');
    });

    test('complete + complete gleichzeitig', () async {
      port.files['e.md'] = '- [ ] Brot\n- [ ] Eier\n';
      await Future.wait([
        run('lists__complete_item', {'list': 'Einkaufen', 'item': 'Brot'}),
        run('lists__complete_item', {'list': 'Einkaufen', 'item': 'Eier'}),
      ]);
      expect(port.files['e.md'], '- [x] Brot\n- [x] Eier\n');
    });

    test('add + Undo eines anderen add gleichzeitig', () async {
      final first = await run('lists__add_items', {
        'list': 'Einkaufen',
        'items': ['Milch'],
      });
      await Future.wait([
        first.undo!(),
        run('lists__add_items', {
          'list': 'Einkaufen',
          'items': ['Eier'],
        }),
      ]);
      expect(port.files['e.md'], '- [ ] Brot\n- [ ] Eier\n');
    });

    test('Fehler in einem Aufruf blockiert die Warteschlange nicht', () async {
      port.failNext('write');
      final results = await Future.wait([
        run('lists__add_items', {
          'list': 'Einkaufen',
          'items': ['A'],
        }),
        run('lists__add_items', {
          'list': 'Einkaufen',
          'items': ['B'],
        }),
      ]);
      expect(results.first.isError, isTrue);
      expect(results.last.isError, isFalse);
      expect(port.files['e.md'], '- [ ] Brot\n- [ ] B\n');
    });
  });

  group('2: höhere Trefferstufe schlägt offen-vor-erledigt', () {
    setUp(() => port.files['e.md'] = '- [x] Milch\n- [ ] Milchreis\n');

    test('complete „Milch“: schon erledigt, Milchreis bleibt offen', () async {
      final o = await run('lists__complete_item', {
        'list': 'Einkaufen',
        'item': 'Milch',
      });
      expect(data(o)['already_done'], 'Milch');
      expect(port.files['e.md'], '- [x] Milch\n- [ ] Milchreis\n');
    });

    test('remove „Milch“ entfernt den genauen (erledigten) Treffer', () async {
      await run('lists__remove_item', {'list': 'Einkaufen', 'item': 'Milch'});
      expect(port.files['e.md'], '- [ ] Milchreis\n');
    });

    test('gleiche Stufe: offen vor erledigt', () async {
      port.files['e.md'] = '- [x] Milch\n- [ ] milch\n';
      await run('lists__remove_item', {'list': 'Einkaufen', 'item': 'Milch'});
      expect(port.files['e.md'], '- [x] Milch\n');
    });
  });

  group('3: Teiltreffer nur an Wortgrenzen, bei Schreib-Tools Rückfrage', () {
    test('„Arbeit“ trifft nicht „Hausarbeit“', () async {
      defs = [ListDefinition(id: 'h', name: 'Hausarbeit', target: 'h.md')];
      final o = await run('lists__add_items', {
        'list': 'Arbeit',
        'items': ['x'],
      });
      expect(o.isError, isTrue);
      expect(o.text, contains('Keine Liste'));
    });

    test('„Eier“ trifft nicht „Eierlikör“', () async {
      port.files['e.md'] = '- [ ] Eierlikör\n';
      final o = await run('lists__complete_item', {
        'list': 'Einkaufen',
        'item': 'Eier',
      });
      expect(o.isError, isTrue);
      expect(o.text, contains('steht nicht'));
      expect(port.files['e.md'], '- [ ] Eierlikör\n');
    });

    test(
      '„Einkaufsliste“ → „Einkauf Baumarkt“: Lesen ja, Schreiben fragt nach',
      () async {
        defs = [
          ListDefinition(id: 'b', name: 'Einkauf Baumarkt', target: 'e.md'),
        ];
        final read = await run('lists__get_items', {'list': 'Einkaufsliste'});
        expect(read.isError, isFalse);
        for (final (name, args) in [
          (
            'lists__add_items',
            {
              'items': ['Schrauben'],
            },
          ),
          ('lists__complete_item', {'item': 'Brot'}),
          ('lists__remove_item', {'item': 'Brot'}),
          ('lists__clear_completed', <String, Object?>{}),
        ]) {
          final o = await run(name, {'list': 'Einkaufsliste', ...args});
          expect(o.isError, isTrue, reason: name);
          expect(
            o.text,
            contains('Meintest du die Liste „Einkauf Baumarkt“'),
            reason: name,
          );
        }
        expect(port.writes, 0);
      },
    );

    test('Eintrag nur über Wortteil: Rückfrage statt Abhaken', () async {
      port.files['e.md'] = '- [ ] Milch (1 l)\n';
      final o = await run('lists__complete_item', {
        'list': 'Einkaufen',
        'item': 'Milch',
      });
      expect(o.isError, isTrue);
      expect(o.text, contains('Meintest du „Milch (1 l)“'));
      expect(port.writes, 0);
    });

    test('Wortteile unter 3 Zeichen treffen nicht', () async {
      port.files['e.md'] = '- [ ] Milch (1 l)\n';
      final o = await run('lists__remove_item', {
        'list': 'Einkaufen',
        'item': 'l',
      });
      expect(o.text, contains('steht nicht'));
    });

    test(
      'gleiche Textzeile doppelt: erste gilt, keine Mehrdeutigkeit',
      () async {
        port.files['e.md'] = '- [ ] Brot\n- [ ] Brot\n';
        await run('lists__complete_item', {
          'list': 'Einkaufen',
          'item': 'brot',
        });
        expect(port.files['e.md'], '- [x] Brot\n- [ ] Brot\n');
      },
    );
  });

  test(
    '4: Undo nach angelegtem Abschnitt behält vorhandene Leerzeile',
    () async {
      port.files['p.md'] = '# P\nText\n\n';
      final o = await run('lists__add_items', {
        'list': 'Projekt',
        'items': ['A'],
      });
      expect(port.files['p.md'], '# P\nText\n\n## Todo\n- [ ] A\n');
      await o.undo!();
      expect(port.files['p.md'], '# P\nText\n\n');
    },
  );

  group('5: Remove-Undo-Anker', () {
    test('Leerzeilen zwischen Vorgänger und Eintrag bleiben', () async {
      port.files['e.md'] = 'Text\n\n- [ ] A\n- [ ] B\n';
      final o = await run('lists__remove_item', {
        'list': 'Einkaufen',
        'item': 'A',
      });
      port.files['e.md'] = 'Neu\n${port.files['e.md']!}';
      await o.undo!();
      expect(port.files['e.md'], 'Neu\nText\n\n- [ ] A\n- [ ] B\n');
    });

    test('Vorgänger weg: Nachfolger als Anker', () async {
      port.files['e.md'] = 'Kopf\n- [ ] A\n- [ ] B\n';
      final o = await run('lists__remove_item', {
        'list': 'Einkaufen',
        'item': 'A',
      });
      port.files['e.md'] = 'Anders\nZeile\n- [ ] B\n';
      await o.undo!();
      expect(port.files['e.md'], 'Anders\nZeile\n- [ ] A\n- [ ] B\n');
    });

    test('Suche nur im Abschnitt', () async {
      port.files['p.md'] = '## Ideen\n- [ ] X\n## Todo\n- [ ] X\n- [ ] A\n';
      final o = await run('lists__remove_item', {
        'list': 'Projekt',
        'item': 'A',
      });
      port.files['p.md'] = 'Oben\n${port.files['p.md']!}';
      await o.undo!();
      expect(
        port.files['p.md'],
        'Oben\n## Ideen\n- [ ] X\n## Todo\n- [ ] X\n- [ ] A\n',
      );
    });

    test(
      '7: entfernte letzte Zeile ohne Umbruch, danach nicht mehr am Ende',
      () async {
        port.files['e.md'] = '- [ ] A\n- [ ] B';
        final o = await run('lists__remove_item', {
          'list': 'Einkaufen',
          'item': 'B',
        });
        port.files['e.md'] = '- [ ] A\n- [ ] C\n';
        await o.undo!();
        expect(port.files['e.md'], '- [ ] A\n- [ ] B\n- [ ] C\n');
      },
    );
  });

  test('6: teilweises Undo wird gemeldet, Rest trotzdem entfernt', () async {
    final o = await run('lists__add_items', {
      'list': 'Einkaufen',
      'items': ['Milch', 'Eier'],
    });
    port.files['e.md'] = port.files['e.md']!.replaceFirst(
      '- [ ] Eier\n',
      '- [x] Eier\n',
    );
    await expectLater(
      o.undo!(),
      throwsA(
        isA<PortException>().having(
          (e) => e.message,
          'message',
          contains('1 von 2'),
        ),
      ),
    );
    expect(port.files['e.md'], '- [ ] Brot\n- [x] Eier\n');
  });

  test('11: Duplikate mit ae/oe/ue', () async {
    port.files['e.md'] = '- [ ] Müsli\n- [ ] Käse\n- [ ] Öl\n';
    final o = await run('lists__add_items', {
      'list': 'Einkaufen',
      'items': ['Muesli', 'Kaese', 'Oel'],
    });
    expect(data(o)['already_present'], ['Muesli', 'Kaese', 'Oel']);
  });

  test('13: fehlende Datei wird gemeldet', () async {
    defs = [ListDefinition(id: 'n', name: 'Neu', target: 'neu.md')];
    final o = await run('lists__get_items', {'list': 'Neu'});
    expect(data(o)['missing_file'], isTrue);
    final ok = await run('lists__get_items', {'list': 'Neu'});
    expect(ok.isError, isFalse);
    port.files['neu.md'] = '';
    expect(
      data(await run('lists__get_items', {'list': 'Neu'}))
          .containsKey('missing_file'),
      isFalse,
    );
  });

  group('Markdown-Grenzfälle (7–9)', () {
    test('Frontmatter endet auch mit „...“', () {
      final doc = MarkdownList.parse('---\n- [ ] yaml\n...\n- [ ] echt\n');
      expect(doc.items().map((i) => i.text), ['echt']);
    });

    test('eingerückte Überschrift beendet Unterzeilen', () {
      final items = MarkdownList.parse('- [ ] A\n  ## H\n  - [ ] x\n').items();
      expect(items.first.end, 1);
    });

    test('Überschrift beendet Unterzeilen', () {
      final items = MarkdownList.parse('- [ ] A\n  text\n## H\n  - [ ] x\n')
          .items();
      expect(items.first.end, 2);
    });

    test(
      'BOM vor der ersten Aufgabe: erkannt, abhaken und einfügen behalten BOM',
      () {
        final doc = MarkdownList.parse('﻿- [ ] a\n');
        expect(doc.items().single.text, 'a');
        doc.setDone(0, true);
        expect(doc.toString(), '﻿- [x] a\n');
        final p = doc.insertionPoint(doc.scope(null)!);
        doc.insert(p.at, ['${p.prefix}[ ] b']);
        expect(doc.toString(), '﻿- [x] a\n- [ ] b\n');
      },
    );

    test('eingerückter Codezaun in einer Liste', () {
      final items = MarkdownList.parse(
        '- [ ] A\n    ```\n    - [ ] code\n    ```\n- [ ] B\n',
      ).items();
      expect(items.map((i) => i.text), ['A', 'B']);
    });

    test('Zitate, Callouts und Sonderstatus zählen nicht', () {
      final items = MarkdownList.parse(
        '> - [ ] zitat\n> [!todo]\n> - [ ] callout\n- [-] abgebrochen\n- [/] halb\n- [ ] echt\n',
      ).items();
      expect(items.map((i) => i.text), ['echt']);
    });
  });
}
