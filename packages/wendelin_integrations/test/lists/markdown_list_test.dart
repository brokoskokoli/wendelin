import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Adds [items] the way `lists__add_items` does.
String add(String content, List<String> items, {String? section}) {
  final doc = MarkdownList.parse(content);
  final range = doc.scope(section)!;
  final p = doc.insertionPoint(range);
  doc.insert(p.at, [for (final i in items) '${p.prefix}[ ] $i']);
  return doc.toString();
}

void main() {
  group('Rundreise ohne Änderung ist zeichengenau', () {
    const samples = {
      'leer': '',
      'nur Umbruch': '\n',
      'LF': '# A\n- [ ] x\n\ntext\n',
      'CRLF': '# A\r\n- [ ] x\r\n\r\ntext\r\n',
      'CR': '# A\r- [ ] x\r',
      'gemischt': 'a\r\nb\nc\rd',
      'ohne Schlussumbruch': '- [ ] x\n- [x] y',
      'BOM und Frontmatter': '﻿---\ntitle: x\n---\n- [ ] a\n',
      'Leerzeichen am Zeilenende': '- [ ] a  \n  \n\t\n',
      'Unicode': '- [ ] Grüße 🥛\n',
    };
    samples.forEach((name, content) {
      test(name, () {
        expect(MarkdownList.parse(content).toString(), content);
      });
    });
  });

  group('Einträge erkennen', () {
    final cases = <String, (String, List<String>)>{
      'Markerarten und Häkchen': (
        '- [ ] a\n* [x] b\n+ [X] c\n1. [ ] d\n2) [ ] e\n',
        ['a', '✓b', '✓c', 'd', 'e'],
      ),
      'keine Aufgaben': ('- a\n-[ ] b\n- [] c\n- [y] d\n[ ] e\n', []),
      'Frontmatter wird ignoriert': (
        '---\n- [ ] yaml\n---\n- [ ] echt\n',
        ['echt'],
      ),
      'Codeblöcke werden ignoriert': (
        '```md\n- [ ] code\n```\n~~~\n- [ ] tilde\n~~~\n- [ ] echt\n',
        ['echt'],
      ),
      'verschachtelt': (
        '- [ ] A\n  - [x] A1\n\t- [ ] A2\n- [ ] B\n',
        ['A', '✓A1', 'A2', 'B'],
      ),
      'Text wird getrimmt': ('- [ ]   Milch  \n', ['Milch']),
      'CRLF': ('- [ ] a\r\n- [x] b\r\n', ['a', '✓b']),
      'nicht geschlossenes Frontmatter zählt nicht als Frontmatter': (
        '---\n- [ ] a\n',
        ['a'],
      ),
    };
    cases.forEach((name, c) {
      test(name, () {
        final items = MarkdownList.parse(c.$1).items();
        expect([for (final i in items) '${i.done ? '✓' : ''}${i.text}'], c.$2);
      });
    });

    test('Unterzeilen gehören zum Eintrag', () {
      final items = MarkdownList.parse(
        '- [ ] A\n  Notiz\n\n  - [ ] A1\nText\n- [ ] B',
      ).items();
      expect(items.first.end, 4);
      expect(items[1].end, 4);
      expect(items.last.end, 6);
    });
  });

  group('Hinzufügen', () {
    final cases = <String, (String, List<String>, String?, String)>{
      'ans Ende des ersten Aufgabenblocks': (
        '# Einkaufen\n- [ ] Milch\n- [x] Brot\n\nNotizen\n- [ ] später\n',
        ['Eier'],
        null,
        '# Einkaufen\n- [ ] Milch\n- [x] Brot\n- [ ] Eier\n\nNotizen\n- [ ] später\n',
      ),
      'CRLF bleibt CRLF': (
        '- [ ] A\r\n- [ ] B\r\n',
        ['C', 'D'],
        null,
        '- [ ] A\r\n- [ ] B\r\n- [ ] C\r\n- [ ] D\r\n',
      ),
      'fehlender Schlussumbruch bleibt fehlend': (
        '- [ ] A',
        ['B'],
        null,
        '- [ ] A\n- [ ] B',
      ),
      'fehlender Schlussumbruch mit CRLF': (
        'x\r\n- [ ] A',
        ['B'],
        null,
        'x\r\n- [ ] A\r\n- [ ] B',
      ),
      'ohne Aufgaben: nach der letzten Textzeile': (
        '# Titel\nText\n\n\n',
        ['X'],
        null,
        '# Titel\nText\n- [ ] X\n\n\n',
      ),
      'leere Datei': ('', ['X'], null, '- [ ] X\n'),
      'nur Frontmatter': (
        '---\ntags: [a]\n---\n',
        ['X'],
        null,
        '---\ntags: [a]\n---\n- [ ] X\n',
      ),
      'verschachtelter erster Block': (
        '- [ ] A\n  - [ ] A1\n  Notiz\n- [ ] B\n\n- [ ] Z\n',
        ['C'],
        null,
        '- [ ] A\n  - [ ] A1\n  Notiz\n- [ ] B\n- [ ] C\n\n- [ ] Z\n',
      ),
      'Markerstil und Einrückung des Blocks': (
        'Liste:\n  * [ ] A\n',
        ['B'],
        null,
        'Liste:\n  * [ ] A\n  * [ ] B\n',
      ),
      'Aufgaben im Codeblock zählen nicht': (
        '```\n- [ ] code\n```\n- [ ] echt\nText\n',
        ['X'],
        null,
        '```\n- [ ] code\n```\n- [ ] echt\n- [ ] X\nText\n',
      ),
      'Abschnitt: erster Block im Abschnitt': (
        '# Projekt\n- [ ] alt\n## Todo\n- [ ] T1\n\n## Erledigt\n- [x] D\n',
        ['N'],
        'Todo',
        '# Projekt\n- [ ] alt\n## Todo\n- [ ] T1\n- [ ] N\n\n## Erledigt\n- [x] D\n',
      ),
      'Abschnitt ohne Aufgaben: vor Leerzeilen und nächster Überschrift': (
        '## Todo\nBeschreibung\n\n## Weiter\n- [ ] x\n',
        ['N'],
        '## todo',
        '## Todo\nBeschreibung\n- [ ] N\n\n## Weiter\n- [ ] x\n',
      ),
      'leerer Abschnitt direkt unter der Überschrift': (
        '## Todo\n## Weiter\n',
        ['N'],
        'Todo',
        '## Todo\n- [ ] N\n## Weiter\n',
      ),
      'Abschnitt umfasst tiefere Überschriften': (
        '## Todo\n### Bald\n- [ ] a\n## Weiter\n',
        ['N'],
        'Todo',
        '## Todo\n### Bald\n- [ ] a\n- [ ] N\n## Weiter\n',
      ),
    };
    cases.forEach((name, c) {
      test(name, () {
        expect(add(c.$1, c.$2, section: c.$3), c.$4);
      });
    });

    test('fehlender Abschnitt: scope ist null', () {
      expect(MarkdownList.parse('# A\n').scope('Todo'), isNull);
      expect(MarkdownList.parse('```\n# Todo\n```\n').scope('Todo'), isNull);
    });
  });

  group('Abhaken und Entfernen', () {
    test('setDone ändert nur das Kästchen', () {
      final doc = MarkdownList.parse('1.  [ ]   Milch  \r\n- [x] Brot');
      doc.setDone(0, true);
      doc.setDone(1, false);
      expect(doc.toString(), '1.  [x]   Milch  \r\n- [ ] Brot');
    });

    test('Entfernen samt Unterzeilen', () {
      final doc = MarkdownList.parse('- [ ] A\n  - [ ] A1\n- [ ] B\n');
      final a = doc.items().first;
      final removed = doc.remove(a.line, a.end);
      expect(doc.toString(), '- [ ] B\n');
      expect(removed.join(), '- [ ] A\n  - [ ] A1\n');
    });

    test(
      'letzte Zeile ohne Umbruch entfernen: neue letzte Zeile ohne Umbruch',
      () {
        final doc = MarkdownList.parse('- [ ] A\r\n- [ ] B');
        doc.remove(1, 2);
        expect(doc.toString(), '- [ ] A');
      },
    );

    test('findLine wählt die nächstgelegene Zeile', () {
      final doc = MarkdownList.parse('x\ny\nx\nz\nx\n');
      expect(doc.findLine('x', 3), 2);
      expect(doc.findLine('x', 4), 4);
      expect(doc.findLine('q', 0), isNull);
    });

    test('Standardzeilenende: erstes gefundenes, sonst LF', () {
      expect(MarkdownList.parse('a\r\nb\n').defaultEol, '\r\n');
      expect(MarkdownList.parse('a').defaultEol, '\n');
      expect(MdLine('a', '\n').toString(), 'a\n');
    });

    test('ListItem.toString', () {
      expect(
        MarkdownList.parse('- [x] a').items().single.toString(),
        contains('x'),
      );
    });
  });
}
