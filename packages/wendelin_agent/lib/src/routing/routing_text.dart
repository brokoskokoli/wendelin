import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart' show foldLetter;

/// A request text prepared for rule matching (ADR 0009 §1).
///
/// [normalized] is lower case, diacritics are folded (`ä` → `a`, `é` → `e`,
/// `ß` → `ss`), every run of characters that are neither letters nor digits
/// becomes one space, and leading/trailing spaces are dropped. So
/// „Claude, trag …“ and „claude trag …“ look the same to a rule.
///
/// Every character of [normalized] remembers where it came from in
/// [original], so a match can be removed from the original text
/// (`stripTrigger`).
@immutable
final class RoutingText {
  /// Normalizes [original].
  factory RoutingText(String original) {
    final out = StringBuffer();
    final starts = <int>[];
    final ends = <int>[];
    var pendingSpace = false;
    var i = 0;
    for (final rune in original.runes) {
      final len = rune > 0xFFFF ? 2 : 1;
      final char = String.fromCharCode(rune);
      if (_mark.hasMatch(char)) {
        // Combining mark (decomposed umlaut): dropped, no separator.
      } else if (_wordChar.hasMatch(char)) {
        if (pendingSpace && out.isNotEmpty) {
          out.write(' ');
          starts.add(i);
          ends.add(i);
        }
        pendingSpace = false;
        for (final unit in _fold(char.toLowerCase()).codeUnits) {
          out.writeCharCode(unit);
          starts.add(i);
          ends.add(i + len);
        }
      } else {
        pendingSpace = true;
      }
      i += len;
    }
    return RoutingText._(original, out.toString(), starts, ends);
  }

  RoutingText._(this.original, this.normalized, this._starts, this._ends);

  /// The text as entered or transcribed.
  final String original;

  /// The normalized text (see class doc).
  final String normalized;

  final List<int> _starts;
  final List<int> _ends;

  /// Normalizes a rule word or phrase the same way as a request text.
  static String normalize(String text) => RoutingText(text).normalized;

  /// The first occurrence of the normalized [phrase] as whole words at or
  /// after [from], or `null`.
  TriggerSpan? findPhrase(String phrase, {int from = 0}) {
    final p = normalize(phrase);
    if (p.isEmpty) return null;
    var at = normalized.indexOf(p, from);
    while (at >= 0) {
      final end = at + p.length;
      if (_boundaryBefore(at) && _boundaryAfter(end)) {
        return TriggerSpan(at, end);
      }
      at = normalized.indexOf(p, at + 1);
    }
    return null;
  }

  /// The span of the normalized [phrase] if the text starts with it as
  /// whole words, else `null`.
  TriggerSpan? startsWithPhrase(String phrase) {
    final p = normalize(phrase);
    if (p.isEmpty || !normalized.startsWith(p)) return null;
    return _boundaryAfter(p.length) ? TriggerSpan(0, p.length) : null;
  }

  bool _boundaryBefore(int at) => at == 0 || normalized[at - 1] == ' ';

  bool _boundaryAfter(int end) =>
      end == normalized.length || normalized[end] == ' ';

  /// [original] with the [spans] (positions in [normalized]) removed, plus
  /// separators that would be left dangling („Claude, trag …“ → „trag …“).
  /// Returns `null` if nothing with letters or digits would remain; the
  /// caller then keeps the original text.
  String? without(Iterable<TriggerSpan> spans) {
    final cut = <(int, int)>[];
    for (final s in spans) {
      var start = s.start;
      var end = s.end;
      while (start < end && normalized[start] == ' ') {
        start++;
      }
      while (end > start && normalized[end - 1] == ' ') {
        end--;
      }
      if (start == end) continue;
      final from = _starts[start];
      var to = _ends[end - 1];
      // Trailing separators: „Claude, …“, „Claude: …“, „Fable – …“.
      while (to < original.length && _trailing.hasMatch(original[to])) {
        to++;
      }
      cut.add((from, to));
    }
    if (cut.isEmpty) return original;
    cut.sort((a, b) => a.$1.compareTo(b.$1));
    final b = StringBuffer();
    var pos = 0;
    for (final (from, to) in cut) {
      if (from > pos) b.write(original.substring(pos, from));
      if (to > pos) pos = to;
    }
    b.write(original.substring(pos));
    final rest = b
        .toString()
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r' ([,.;:!?])'), r'$1')
        .trim();
    final cleaned = rest.replaceFirst(RegExp(r'^[,.;:!?\-–—\s]+'), '');
    if (!_wordChar.hasMatch(cleaned)) return null;
    return cleaned;
  }

  @override
  bool operator ==(Object other) =>
      other is RoutingText && other.original == original;

  @override
  int get hashCode => original.hashCode;

  @override
  String toString() => 'RoutingText("$normalized")';

  static final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final _mark = RegExp(r'^\p{M}$', unicode: true);
  static final _trailing = RegExp(r'[\s,.;:!?\-–—]');

  static String _fold(String lower) =>
      lower.length != 1 ? lower.split('').map(_fold).join() : foldLetter(lower);
}

/// A range `[start, end)` in [RoutingText.normalized].
@immutable
final class TriggerSpan {
  /// Creates a span.
  const TriggerSpan(this.start, this.end);

  /// First position.
  final int start;

  /// Position after the last character.
  final int end;

  @override
  bool operator ==(Object other) =>
      other is TriggerSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TriggerSpan($start, $end)';
}
