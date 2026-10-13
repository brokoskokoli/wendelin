// Datenhüllen für Inhalte aus fremden Quellen (Web, Notizen): Inhalte sind
// Daten, keine Anweisungen.

/// Neutralizes opening and closing tags named [tags] inside [text] (also
/// with whitespace or other case, e.g. `< /WEB_CONTENT >`), so content can
/// neither end its data block early nor fake a new one.
String escapeDataTags(String text, List<String> tags) {
  final names = tags.map(RegExp.escape).join('|');
  return text.replaceAllMapped(
    RegExp('<(\\s*/?\\s*(?:$names))', caseSensitive: false),
    (m) => '&lt;${m[1]}',
  );
}

/// [value] escaped for a double-quoted attribute of a data tag.
String escapeDataAttr(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('\n', ' ')
    .replaceAll('\r', ' ');
