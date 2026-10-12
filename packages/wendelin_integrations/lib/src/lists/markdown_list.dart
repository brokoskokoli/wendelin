// Markdown-Aufgabenlisten lesen und zeilenbasiert ändern.
//
// Die Datei wird in Zeilen samt ihrem Zeilenende zerlegt; nur die Zeilen,
// die eine Operation betrifft, ändern sich. Alles andere (Frontmatter,
// Überschriften, Text, CRLF, fehlender Zeilenumbruch am Ende, BOM) bleibt
// Zeichen für Zeichen erhalten.

import 'matching.dart';

final _task = RegExp(
  r'^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)\[([ xX])\]([ \t]+|$)(.*)$',
);
final _listLine = RegExp(r'^[ \t]*([-*+]|\d{1,9}[.)])([ \t]|$)');
final _heading = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$');
final _fence = RegExp(r'^[ \t]*(`{3,}|~{3,})');

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

/// A task line (`- [ ] Milch`) found in a [MarkdownList].
final class ListItem {
  ListItem._(this.line, this.end, this.indent, this.done, this.text);

  /// Index of the task line.
  final int line;

  /// Exclusive end of the item including nested lines below it.
  final int end;

  /// Width of the leading whitespace.
  final int indent;

  /// Whether the box is checked.
  final bool done;

  /// Item text after the checkbox.
  final String text;

  @override
  String toString() => 'ListItem($line, ${done ? 'x' : ' '}, $text)';
}

/// A Markdown file viewed as task list, optionally restricted to the
/// section below a heading.
final class MarkdownList {
  /// Splits [content] into lines and finds frontmatter, code blocks and
  /// headings.
  MarkdownList.parse(String content) : lines = _split(content) {
    _analyse();
  }

  /// All lines; [toString] joins them back.
  final List<MdLine> lines;

  /// Line ending used for new lines (the first one found, else `\n`).
  String get defaultEol => lines
      .map((l) => l.eol)
      .firstWhere((e) => e.isNotEmpty, orElse: () => '\n');

  final Set<int> _ignored = {};

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

  /// Marks frontmatter and fenced code blocks; task syntax there is
  /// ignored.
  void _analyse() {
    _ignored.clear();
    var i = 0;
    final first = lines.isEmpty ? null : _t(0);
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
      }
    }
    String? fence;
    for (; i < lines.length; i++) {
      final m = _fence.firstMatch(_t(i));
      if (fence != null) {
        _ignored.add(i);
        if (m != null &&
            m[1]![0] == fence[0] &&
            m[1]!.length >= fence.length &&
            _t(i).trim() == m[1]) {
          fence = null;
        }
      } else if (m != null) {
        fence = m[1];
        _ignored.add(i);
      }
    }
  }

  /// The file content.
  @override
  String toString() => lines.join();

  int _indentOf(String text) {
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

  bool _blank(int i) => _t(i).trim().isEmpty;

  /// Text of line [i] without a leading BOM (first line only).
  String _t(int i) => i == 0 && lines[0].text.startsWith('\uFEFF')
      ? lines[0].text.substring(1)
      : lines[i].text;

  /// Heading level of line [i] (1–6), or `null`.
  int? headingLevel(int i) {
    if (_ignored.contains(i)) return null;
    final m = _heading.firstMatch(_t(i));
    return m == null ? null : m[1]!.length;
  }

  /// Lines `[start, end)` of the section below the heading named
  /// [section] (compared loosely), the whole file if [section] is `null`,
  /// or `null` if the heading does not exist.
  ({int start, int end})? scope(String? section) {
    if (section == null) return (start: 0, end: lines.length);
    final wanted = foldText(section.replaceFirst(RegExp(r'^#+\s*'), ''));
    for (var i = 0; i < lines.length; i++) {
      final level = headingLevel(i);
      if (level == null) continue;
      final title = _heading.firstMatch(_t(i))![2] ?? '';
      if (foldText(title) != wanted) continue;
      var end = i + 1;
      while (end < lines.length) {
        final l = headingLevel(end);
        if (l != null && l <= level) break;
        end++;
      }
      return (start: i + 1, end: end);
    }
    return null;
  }

  /// Task items in [range] (default: whole file), in file order.
  List<ListItem> items([({int start, int end})? range]) {
    final r = range ?? (start: 0, end: lines.length);
    final result = <ListItem>[];
    for (var i = r.start; i < r.end; i++) {
      if (_ignored.contains(i)) continue;
      final m = _task.firstMatch(_t(i));
      if (m == null) continue;
      final indent = _indentOf(_t(i));
      result.add(
        ListItem._(
          i,
          _childrenEnd(i, indent, r.end),
          indent,
          m[4] != ' ',
          m[6]!.trim(),
        ),
      );
    }
    return result;
  }

  /// End of the nested lines below line [i] (deeper indented, blank lines
  /// only between them).
  int _childrenEnd(int i, int indent, int limit) {
    var end = i + 1;
    var k = i + 1;
    while (k < limit) {
      if (_blank(k)) {
        k++;
        continue;
      }
      if (_ignored.contains(k) || _indentOf(_t(k)) <= indent) break;
      if (headingLevel(k) != null) break;
      k++;
      end = k;
    }
    return end;
  }

  /// Where new items go inside [range]: after the first block of list
  /// lines, else after the last non-blank line of the range (at least at
  /// its start). Also returns the prefix (indent + marker) of that block.
  ({int at, String prefix}) insertionPoint(({int start, int end}) range) {
    final first = items(range).firstOrNull;
    if (first == null) {
      var at = range.end;
      while (at > range.start && _blank(at - 1)) {
        at--;
      }
      return (at: at, prefix: '- ');
    }
    final m = _task.firstMatch(_t(first.line))!;
    var at = first.line;
    while (at < range.end) {
      if (_blank(at) || _ignored.contains(at) || headingLevel(at) != null) {
        break;
      }
      final isList = _listLine.hasMatch(_t(at));
      if (!isList && _indentOf(_t(at)) <= first.indent) break;
      at++;
    }
    return (at: at, prefix: '${m[1]}${m[2]}${m[3]}');
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
    _analyse();
  }

  /// Removes lines `[start, end)` and returns them. If the removed lines
  /// ended the file without a final line break, the new last line loses
  /// its line break as well.
  List<MdLine> remove(int start, int end) {
    final removed = lines.sublist(start, end);
    final wasEnd = end == lines.length;
    lines.removeRange(start, end);
    if (wasEnd && removed.last.eol.isEmpty && lines.isNotEmpty) {
      lines.last.eol = '';
    }
    _analyse();
    return removed;
  }

  /// Sets the checkbox of the task line [i].
  void setDone(int i, bool done) {
    final m = _task.firstMatch(_t(i))!;
    var box = m[1]!.length + m[2]!.length + m[3]!.length + 1;
    final bom = lines[i].text.length - _t(i).length;
    final t = lines[i].text;
    box += bom;
    lines[i].text =
        '${t.substring(0, box)}${done ? 'x' : ' '}${t.substring(box + 1)}';
  }

  /// Index of the line whose text equals [text] closest to [near], or
  /// `null`.
  int? findLine(String text, int near, {int? from, int? to}) {
    int? best;
    for (var i = from ?? 0; i < (to ?? lines.length); i++) {
      if (lines[i].text != text || _ignored.contains(i)) continue;
      if (best == null || (i - near).abs() < (best - near).abs()) best = i;
    }
    return best;
  }
}
