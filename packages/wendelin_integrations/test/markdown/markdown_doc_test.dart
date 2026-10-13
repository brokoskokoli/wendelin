import 'package:test/test.dart';
import 'package:wendelin_integrations/src/markdown/markdown_doc.dart';

void main() {
  group('Überschriften', () {
    test('ATX mit Ebenen, schließenden # und Einrückung bis 3', () {
      final d = MarkdownDoc.parse(
        '# Eins\n## Zwei ##\n   ### Drei\n    # Code\n#Kein\n###### Sechs\n',
      );
      expect(d.headings.map((h) => (h.line, h.level, h.title)), [
        (0, 1, 'Eins'),
        (1, 2, 'Zwei'),
        (2, 3, 'Drei'),
        (5, 6, 'Sechs'),
      ]);
    });

    test('nicht in Frontmatter und Codeblöcken', () {
      final d = MarkdownDoc.parse(
        '---\n# kein\n---\n# Ja\n```\n# kein\n```\n~~~\n# kein\n~~~\n',
      );
      expect(d.headings.map((h) => h.title), ['Ja']);
      expect(d.frontmatterEnd, 3);
      expect(d.isIgnored(1), isTrue);
      expect(d.isIgnored(3), isFalse);
    });

    test('setext nur wenn eingeschaltet, nur einzeilige Absätze', () {
      const text =
          'Titel\n=====\n\nUnter\n---\nText\nzweite Zeile\n---\n\n- Liste\n---\n'
          '> Zitat\n---\n';
      expect(MarkdownDoc.parse(text).headings, isEmpty);
      final d = MarkdownDoc.parse(text, setext: true);
      expect(d.headings.map((h) => (h.line, h.level, h.title, h.setext)), [
        (0, 1, 'Titel', true),
        (3, 2, 'Unter', true),
      ]);
      expect(d.headings.first.bodyStart, 2);
    });

    test('setext direkt nach Frontmatter und nach Überschrift', () {
      final d = MarkdownDoc.parse(
        '---\na: 1\n---\nOben\n===\nDarunter\n---\n# ATX\nNach\n---\n',
        setext: true,
      );
      expect(d.headings.map((h) => h.title), [
        'Oben',
        'Darunter',
        'ATX',
        'Nach',
      ]);
    });

    test('Frontmatter ohne Ende ist keine', () {
      final d = MarkdownDoc.parse('---\n# Titel\n');
      expect(d.frontmatterEnd, 0);
      expect(d.headings.single.title, 'Titel');
    });

    test('findHeadings vergleicht locker', () {
      final d = MarkdownDoc.parse('## 💡 Ideen\n## Grüße\n## Ideen\n');
      expect(d.findHeadings('ideen').map((h) => h.line), [0, 2]);
      expect(d.findHeadings('## Grüsse').single.line, 1);
      expect(d.findHeadings('Fehlt'), isEmpty);
    });
  });

  group('Abschnitte', () {
    final d = MarkdownDoc.parse(
      '# A\na1\n## B\nb1\n### C\nc1\n## D\nd1\n\n\n# E\n',
    );
    MdHeading h(String t) => d.findHeadings(t).single;

    test('sectionOf schließt Unterabschnitte ein', () {
      expect(d.sectionOf(h('A')), (start: 1, end: 10));
      expect(d.sectionOf(h('B')), (start: 3, end: 6));
      expect(d.sectionOf(h('E')), (start: 11, end: 11));
    });

    test('ownContentOf endet an der nächsten Überschrift', () {
      expect(d.ownContentOf(h('A')), (start: 1, end: 2));
      expect(d.ownContentOf(h('D')), (start: 7, end: 10));
      expect(d.contentEnd(7, 10), 8);
      expect(d.contentEnd(11, 11), 11);
    });

    test('scope wie bei Listen', () {
      expect(d.scope(null), (start: 0, end: 11));
      expect(d.scope('B'), (start: 3, end: 6));
      expect(d.scope('Fehlt'), isNull);
    });
  });

  group('Ändern bleibt byte-genau', () {
    for (final (name, content) in [
      ('LF', '# A\nalt\n# B\n'),
      ('CRLF', '﻿# A\r\nalt\r\n# B\r\n'),
      ('ohne Schlussumbruch', '# A\nalt'),
      ('CR', '# A\ralt\r'),
    ]) {
      test('replace + restore ($name)', () {
        final d = MarkdownDoc.parse(content, setext: true);
        final old = d.replace(1, 2, ['neu 1', 'neu 2']);
        expect(d.toString(), isNot(content));
        expect(d.lines[1].text, 'neu 1');
        d.restore(1, 3, old);
        expect(d.toString(), content);
      });

      test('insert + remove am Ende ($name)', () {
        final d = MarkdownDoc.parse(content);
        d.insert(d.lines.length, ['x', 'y']);
        expect(d.lines.last.text, 'y');
        d.remove(d.lines.length - 2, d.lines.length);
        expect(d.toString(), content);
      });
    }

    test('replace ohne Zeilen = insert; leere neue Zeilen = remove', () {
      final d = MarkdownDoc.parse('a\nb\n');
      expect(d.replace(1, 1, ['x']), isEmpty);
      expect(d.toString(), 'a\nx\nb\n');
      d.replace(1, 2, []);
      expect(d.toString(), 'a\nb\n');
    });

    test('restore mit leerer Liste entfernt', () {
      final d = MarkdownDoc.parse('a\nx\nb\n');
      d.restore(1, 2, []);
      expect(d.toString(), 'a\nb\n');
    });

    test('restore klebt später angehängten Text nicht an', () {
      final d = MarkdownDoc.parse('# A\nalt');
      final old = d.replace(1, 2, ['neu']);
      // Fremde Änderung: hinten wurde etwas angehängt.
      final e = MarkdownDoc.parse('${d.toString()}\nmehr');
      e.restore(1, 2, old);
      expect(e.toString(), '# A\nalt\nmehr');
    });

    test('findBlock: nächstgelegene Fundstelle, auch im Codeblock', () {
      final d = MarkdownDoc.parse('x\ny\n```\nx\ny\n```\nx\ny\n');
      expect(d.findBlock(['x', 'y'], 0), 0);
      expect(d.findBlock(['x', 'y'], 4), 3);
      expect(d.findBlock(['x', 'y'], 7), 6);
      expect(d.findBlock(['x', 'z'], 0), isNull);
      expect(d.findBlock([], 0), isNull);
    });

    test('indentOf zählt Tab als 4', () {
      final d = MarkdownDoc.parse('');
      expect(d.indentOf('\t  x'), 6);
      expect(d.defaultEol, '\n');
    });
  });
}
