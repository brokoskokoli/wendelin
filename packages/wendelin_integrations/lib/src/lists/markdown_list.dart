// Markdown-Aufgabenlisten lesen und zeilenbasiert ändern (auf Basis von
// MarkdownDoc, das Zeilen, Frontmatter, Codeblöcke und Überschriften kennt).

import '../markdown/markdown_doc.dart';

export '../markdown/markdown_doc.dart' show MdLine;

final _task = RegExp(
  r'^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)\[([ xX])\]([ \t]+|$)(.*)$',
);

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
/// section below a heading (ATX headings only).
final class MarkdownList extends MarkdownDoc {
  /// Splits [content] into lines and finds frontmatter, code blocks and
  /// headings.
  MarkdownList.parse(super.content) : super.parse();

  /// Task items in [range] (default: whole file), in file order.
  List<ListItem> items([({int start, int end})? range]) {
    final r = range ?? (start: 0, end: lines.length);
    final result = <ListItem>[];
    for (var i = r.start; i < r.end; i++) {
      if (isIgnored(i)) continue;
      final m = _task.firstMatch(lines[i].text);
      if (m == null) continue;
      final indent = indentOf(lines[i].text);
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
      if (isBlank(k)) {
        k++;
        continue;
      }
      if (isIgnored(k) || indentOf(lines[k].text) <= indent) break;
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
      while (at > range.start && isBlank(at - 1)) {
        at--;
      }
      return (at: at, prefix: '- ');
    }
    final m = _task.firstMatch(lines[first.line].text)!;
    var at = first.line;
    while (at < range.end) {
      if (isBlank(at) || isIgnored(at) || headingLevel(at) != null) {
        break;
      }
      final isList = listLinePattern.hasMatch(lines[at].text);
      if (!isList && indentOf(lines[at].text) <= first.indent) break;
      at++;
    }
    return (at: at, prefix: '${m[1]}${m[2]}${m[3]}');
  }

  /// Sets the checkbox of the task line [i].
  void setDone(int i, bool done) {
    final m = _task.firstMatch(lines[i].text)!;
    final box = m[1]!.length + m[2]!.length + m[3]!.length + 1;
    final t = lines[i].text;
    lines[i].text =
        '${t.substring(0, box)}${done ? 'x' : ' '}${t.substring(box + 1)}';
  }
}
