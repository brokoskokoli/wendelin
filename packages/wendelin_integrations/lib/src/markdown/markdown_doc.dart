// Markdown-Dateien zeilenbasiert lesen und ändern (gemeinsam für Listen und
// Obsidian).
//
// Die Datei wird in Zeilen samt ihrem Zeilenende zerlegt; nur die Zeilen,
// die eine Operation betrifft, ändern sich. Alles andere (Frontmatter,
// Überschriften, Text, CRLF, fehlender Zeilenumbruch am Ende, BOM) bleibt
// Zeichen für Zeichen erhalten.

import '../common/matching.dart';

final _atx = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$');
final _setextUnderline = RegExp(r'^ {0,3}(=+|-+)[ \t]*$');
final _fence = RegExp(r'^[ \t]*(`{3,}|~{3,})');

/// Matches the start of a list line (`- `, `* `, `+ `, `1. `, `1) `).
final listLinePattern = RegExp(r'^[ \t]*([-*+]|\d{1,9}[.)])([ \t]|$)');

/// One line of a file with its own line ending (`\n`, `\r\n`, `\r` or
/// empty for a last line without line break).
final class MdLine {
  /// Creates a line.
  MdLine(this.text, this.eol);

  /// Content without line ending.
  String text;

  /// Line ending.
  String eol;

  @override
  String toString() => '$text$eol';
}

/// A heading found in a [MarkdownDoc].
final class MdHeading {
  /// Creates a heading.
  const MdHeading(this.line, this.level, this.title, {this.setext = false});

  /// Index of the heading line (for setext headings the text line).
  final int line;

  /// Level 1–6.
  final int level;

  /// Heading text without `#` markers, trimmed.
  final String title;

  /// Whether it is a setext heading (text line plus `===`/`---` below).
  final bool setext;

  /// First line after the heading (after the underline for setext).
  int get bodyStart => line + (setext ? 2 : 1);

  @override
  String toString() => 'MdHeading($line, h$level, $title)';
}

/// A Markdown file as a list of lines with their line endings, plus the
/// structure the tools need: frontmatter, fenced code blocks, headings.
///
/// Edits ([insert], [remove], [replace]) change only the given lines and
/// keep everything else byte for byte, including the BOM and a missing
/// final line break.
class MarkdownDoc {
  /// Splits [content] into lines and finds frontmatter, code blocks and
  /// headings. With [setext], `Titel` + `===`/`---` also count as headings
  /// (single-line paragraphs only); otherwise only ATX (`## Titel`).
  MarkdownDoc.parse(String content, {this.setext = false})
    : bom = content.startsWith('﻿') ? '﻿' : '',
      lines = _split(content.startsWith('﻿') ? content.substring(1) : content) {
    analyse();
  }

  /// Whether setext headings are recognized.
  final bool setext;

  /// Byte order mark of the file (kept apart from the lines and put back
  /// in front by [toString]), or empty.
  final String bom;

  /// All lines; [toString] joins them back.
  final List<MdLine> lines;

  /// Line ending used for new lines (the first one found, else `\n`).
  String get defaultEol => lines
      .map((l) => l.eol)
      .firstWhere((e) => e.isNotEmpty, orElse: () => '\n');

  final Set<int> _ignored = {};
  final Map<int, MdHeading> _headings = {};
  int _frontmatterEnd = 0;

  /// Exclusive end of the frontmatter block (`---` … `---`), 0 if none.
  int get frontmatterEnd => _frontmatterEnd;

  /// All headings in file order.
  List<MdHeading> get headings =>
      (_headings.values.toList()..sort((a, b) => a.line.compareTo(b.line)));

  static List<MdLine> _split(String content) {
    final result = <MdLine>[];
    var start = 0;
    for (var i = 0; i < content.length; i++) {
      final c = content.codeUnitAt(i);
      if (c == 0x0A || c == 0x0D) {
        final crlf =
            c == 0x0D &&
            i + 1 < content.length &&
            content.codeUnitAt(i + 1) == 0x0A;
        final eol = crlf ? '\r\n' : String.fromCharCode(c);
        result.add(MdLine(content.substring(start, i), eol));
        if (crlf) i++;
        start = i + 1;
      }
    }
    if (start < content.length) {
      result.add(MdLine(content.substring(start), ''));
    }
    return result;
  }

  /// Recomputes frontmatter, fenced code blocks and headings; edits call
  /// it, subclasses may extend it.
  void analyse() {
    _ignored.clear();
    _headings.clear();
    _frontmatterEnd = 0;
    var i = 0;
    final first = lines.isEmpty ? null : lines[0].text;
    if (first == '---') {
      final close = lines.indexWhere(
        (l) => l.text == '---' || l.text == '...',
        1,
      );
      if (close > 0) {
        for (var k = 0; k <= close; k++) {
          _ignored.add(k);
        }
        i = close + 1;
        _frontmatterEnd = i;
      }
    }
    String? fence;
    for (; i < lines.length; i++) {
      final m = _fence.firstMatch(lines[i].text);
      if (fence != null) {
        _ignored.add(i);
        if (m != null &&
            m[1]![0] == fence[0] &&
            m[1]!.length >= fence.length &&
            lines[i].text.trim() == m[1]) {
          fence = null;
        }
      } else if (m != null) {
        fence = m[1];
        _ignored.add(i);
      }
    }
    for (var k = 0; k < lines.length; k++) {
      if (_ignored.contains(k)) continue;
      final m = _atx.firstMatch(lines[k].text);
      if (m != null) {
        _headings[k] = MdHeading(k, m[1]!.length, (m[2] ?? '').trim());
        continue;
      }
      if (setext && _isSetext(k)) {
        final underline = lines[k + 1].text.trim();
        _headings[k] = MdHeading(
          k,
          underline.startsWith('=') ? 1 : 2,
          lines[k].text.trim(),
          setext: true,
        );
        k++;
      }
    }
  }

  bool _isSetext(int k) {
    if (k + 1 >= lines.length || _ignored.contains(k + 1)) return false;
    final text = lines[k].text;
    if (text.trim().isEmpty || indentOf(text) >= 4) return false;
    if (text.trimLeft().startsWith('>') || listLinePattern.hasMatch(text)) {
      return false;
    }
    if (!_setextUnderline.hasMatch(lines[k + 1].text)) return false;
    // Nur einzeilige Absätze: davor Dateianfang, Leerzeile, Frontmatter oder
    // eine Überschrift.
    final prev = k - 1;
    return prev < _frontmatterEnd ||
        isBlank(prev) ||
        _headings.containsKey(prev) ||
        (prev > 0 && _headings[prev - 1]?.setext == true);
  }

  /// The file content.
  @override
  String toString() => '$bom${lines.join()}';

  /// Width of the leading whitespace of [text] (tab = 4).
  int indentOf(String text) {
    var n = 0;
    for (final c in text.codeUnits) {
      if (c == 0x20) {
        n++;
      } else if (c == 0x09) {
        n += 4;
      } else {
        break;
      }
    }
    return n;
  }

  /// Whether line [i] is empty or whitespace only.
  bool isBlank(int i) => lines[i].text.trim().isEmpty;

  /// Whether line [i] lies in the frontmatter or a fenced code block.
  bool isIgnored(int i) => _ignored.contains(i);

  /// Heading level of line [i] (1–6), or `null`. For setext headings only
  /// the text line counts.
  int? headingLevel(int i) => _headings[i]?.level;

  /// The heading at line [i], or `null`.
  MdHeading? headingAt(int i) => _headings[i];

  /// Headings whose title matches [name] loosely (case, umlauts,
  /// punctuation; leading `#` in [name] ignored).
  List<MdHeading> findHeadings(String name) {
    final wanted = foldText(name.replaceFirst(RegExp(r'^#+\s*'), ''));
    return [
      for (final h in headings)
        if (foldText(h.title) == wanted) h,
    ];
  }

  /// Lines `[start, end)` below [h] up to the next heading of the same or
  /// a higher level (subsections included).
  ({int start, int end}) sectionOf(MdHeading h) {
    var end = h.bodyStart;
    while (end < lines.length) {
      final l = headingLevel(end);
      if (l != null && l <= h.level) break;
      end++;
    }
    return (start: h.bodyStart, end: end);
  }

  /// Lines `[start, end)` of the own content of [h]: up to the next
  /// heading of any level.
  ({int start, int end}) ownContentOf(MdHeading h) {
    var end = h.bodyStart;
    while (end < lines.length && headingLevel(end) == null) {
      end++;
    }
    return (start: h.bodyStart, end: end);
  }

  /// Lines `[start, end)` of the section below the first heading named
  /// [section], the whole file if [section] is `null`, or `null` if the
  /// heading does not exist.
  ({int start, int end})? scope(String? section) {
    if (section == null) return (start: 0, end: lines.length);
    final h = findHeadings(section).firstOrNull;
    return h == null ? null : sectionOf(h);
  }

  /// Index after the last non-blank line in `[start, end)`, at least
  /// [start].
  int contentEnd(int start, int end) {
    var at = end;
    while (at > start && isBlank(at - 1)) {
      at--;
    }
    return at;
  }

  /// Inserts [newLines] (without line endings) before index [at]; new
  /// lines use [eols] or [defaultEol]. Keeps a missing final line break
  /// missing: when appending, the old last line gets [terminator] (default
  /// [defaultEol]) and the new last line none.
  void insert(
    int at,
    List<String> newLines, {
    List<String>? eols,
    String? terminator,
  }) {
    if (newLines.isEmpty) return;
    final eol = defaultEol;
    final created = [
      for (var k = 0; k < newLines.length; k++)
        MdLine(newLines[k], eols?[k] ?? eol),
    ];
    if (at >= lines.length) {
      at = lines.length;
      if (lines.isNotEmpty && lines.last.eol.isEmpty) {
        // Datei endete ohne Zeilenumbruch: der bleibt am neuen Ende weg.
        lines.last.eol = terminator ?? eol;
        created.last.eol = '';
      }
    }
    lines.insertAll(at, created);
    analyse();
  }

  /// Removes lines `[start, end)` and returns them. If the removed lines
  /// ended the file without a final line break, the new last line loses
  /// its line break as well.
  List<MdLine> remove(int start, int end) {
    final removed = lines.sublist(start, end);
    final wasEnd = end == lines.length;
    lines.removeRange(start, end);
    if (wasEnd &&
        removed.isNotEmpty &&
        removed.last.eol.isEmpty &&
        lines.isNotEmpty) {
      lines.last.eol = '';
    }
    analyse();
    return removed;
  }

  /// Replaces lines `[start, end)` by [newLines] and returns the old ones.
  /// The last new line keeps the line ending of the last old line (so a
  /// missing final line break stays missing).
  List<MdLine> replace(int start, int end, List<String> newLines) {
    if (start == end) {
      insert(start, newLines);
      return const [];
    }
    final old = lines.sublist(start, end);
    final eol = defaultEol;
    final created = [
      for (var k = 0; k < newLines.length; k++)
        MdLine(newLines[k], k == newLines.length - 1 ? old.last.eol : eol),
    ];
    if (created.isEmpty) return remove(start, end);
    lines.replaceRange(start, end, created);
    analyse();
    return old;
  }

  /// Puts the lines [old] (e.g. returned by [replace]) back in place of
  /// lines `[start, end)`: texts and line endings as in [old], except the
  /// last line, which keeps the line ending of the replaced last line (so
  /// text added behind it in the meantime is not glued on).
  void restore(int start, int end, List<MdLine> old) {
    if (old.isEmpty) {
      remove(start, end);
      return;
    }
    final last = end > start ? lines[end - 1].eol : old.last.eol;
    lines.replaceRange(start, end, [
      for (var k = 0; k < old.length; k++)
        MdLine(old[k].text, k == old.length - 1 ? last : old[k].eol),
    ]);
    analyse();
  }

  /// Index of the line whose text equals [text] closest to [near], or
  /// `null`. Lines in frontmatter and code blocks are skipped.
  int? findLine(String text, int near, {int? from, int? to}) {
    int? best;
    for (var i = from ?? 0; i < (to ?? lines.length); i++) {
      if (lines[i].text != text || _ignored.contains(i)) continue;
      if (best == null || (i - near).abs() < (best - near).abs()) best = i;
    }
    return best;
  }

  /// Start index of the run of lines equal to [block] closest to [near],
  /// or `null`. Unlike [findLine] this also looks into code blocks (the
  /// block may itself contain a fence).
  int? findBlock(List<String> block, int near) {
    if (block.isEmpty) return null;
    int? best;
    for (var i = 0; i + block.length <= lines.length; i++) {
      var ok = true;
      for (var k = 0; k < block.length && ok; k++) {
        ok = lines[i + k].text == block[k];
      }
      if (!ok) continue;
      if (best == null || (i - near).abs() < (best - near).abs()) best = i;
    }
    return best;
  }
}
