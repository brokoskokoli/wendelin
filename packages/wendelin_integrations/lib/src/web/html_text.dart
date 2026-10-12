import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

const _dropped = {
  'script',
  'style',
  'noscript',
  'template',
  'svg',
  'canvas',
  'iframe',
  'object',
  'embed',
  'head',
  'nav',
  'footer',
  'aside',
  'form',
  'button',
  'select',
};

const _blocks = {
  'address',
  'article',
  'blockquote',
  'dd',
  'div',
  'dl',
  'dt',
  'figcaption',
  'figure',
  'header',
  'hr',
  'li',
  'main',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'tr',
  'ul',
  'br',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
};

/// Readable text of an HTML page: title plus body text without scripts,
/// styles, navigation and forms. Headings become `#` lines, list items
/// `- ` lines; whitespace is collapsed.
({String? title, String text}) htmlToText(String source) {
  final doc = html.parse(source);
  final title = doc.querySelector('title')?.text.trim();
  final out = StringBuffer();
  void walk(Node node) {
    if (node is Text) {
      out.write(node.data.replaceAll(RegExp(r'\s+'), ' '));
      return;
    }
    if (node is! Element) {
      node.nodes.forEach(walk);
      return;
    }
    final tag = node.localName ?? '';
    if (_dropped.contains(tag) || node.attributes['hidden'] != null) return;
    final block = _blocks.contains(tag);
    if (block) out.write('\n');
    if (tag.length == 2 && tag[0] == 'h' && '123456'.contains(tag[1])) {
      out.write('${'#' * int.parse(tag[1])} ');
    } else if (tag == 'li') {
      out.write('- ');
    } else if (tag == 'td' || tag == 'th') {
      out.write(' | ');
    }
    node.nodes.forEach(walk);
    if (block) out.write('\n');
  }

  walk(doc.body ?? doc.documentElement ?? doc);
  final lines = out
      .toString()
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r' {2,}'), ' ').trim())
      .where((l) => l.isNotEmpty && l != '-' && l != '|');
  return (
    title: title == null || title.isEmpty ? null : title,
    text: lines.join('\n'),
  );
}
