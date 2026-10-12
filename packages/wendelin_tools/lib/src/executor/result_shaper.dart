import 'package:wendelin_core/wendelin_core.dart';

/// Prepares content produced by a tool before it goes to the model:
/// truncates long text and puts everything in a `<tool_data>` envelope, so
/// the model treats it as data and not as instructions (prompt injection).
///
/// Only used for outcomes returned by tools. Outcomes the runtime creates
/// itself (cancelled, declined, unknown tool, …) are passed on unchanged.
final class ResultShaper {
  /// Creates a shaper that keeps at most [maxChars] characters of text and
  /// wraps the result unless [envelope] is `false`.
  const ResultShaper({this.maxChars = 8000, this.envelope = true});

  /// Maximum number of text characters (over all text blocks) kept.
  final int maxChars;

  /// Whether results are put in the `<tool_data>` envelope. Only switched
  /// off where a caller needs the raw tool text (tests); never in the app.
  final bool envelope;

  /// Opening tag of the envelope for [tool].
  static String openTag(String tool) => '<tool_data tool="$tool">';

  /// Closing tag of the envelope.
  static const closeTag = '</tool_data>';

  /// Truncation marker appended to cut text.
  static String marker(int kept, int total) =>
      '[gekürzt: $kept von $total Zeichen]';

  static final _tagLike = RegExp('<(/?)(tool_data)', caseSensitive: false);

  /// [outcome] truncated and wrapped for [tool]; `summary`, `undo` and
  /// `isError` are kept.
  ToolOutcome shape(String tool, ToolOutcome outcome) => ToolOutcome(
    content: envelope
        ? _wrap(tool, _truncate(outcome.content))
        : _truncate(outcome.content),
    isError: outcome.isError,
    summary: outcome.summary,
    undo: outcome.undo,
  );

  List<ContentBlock> _truncate(List<ContentBlock> content) {
    final total = content.whereType<TextBlock>().fold<int>(
      0,
      (sum, b) => sum + b.text.length,
    );
    if (total <= maxChars) return content;
    var budget = maxChars;
    final out = <ContentBlock>[];
    for (final block in content) {
      if (block is! TextBlock) {
        out.add(block);
        continue;
      }
      if (budget <= 0) continue;
      final keep = block.text.length <= budget ? block.text.length : budget;
      out.add(TextBlock(_cut(block.text, keep)));
      budget -= keep;
    }
    out.add(TextBlock('\n${marker(maxChars, total)}'));
    return out;
  }

  /// Cuts [text] to [keep] code units without splitting a surrogate pair.
  static String _cut(String text, int keep) {
    if (keep >= text.length) return text;
    final last = text.codeUnitAt(keep - 1);
    final splitsPair = last >= 0xD800 && last <= 0xDBFF;
    return text.substring(0, splitsPair ? keep - 1 : keep);
  }

  List<ContentBlock> _wrap(String tool, List<ContentBlock> content) {
    // Neutralise tags inside the data, so it cannot close the envelope.
    final escaped = [
      for (final b in content)
        if (b is TextBlock)
          TextBlock(b.text.replaceAllMapped(_tagLike, (m) => '‹${m[1]}${m[2]}'))
        else
          b,
    ];
    final open = '${openTag(tool)}\n';
    const close = '\n$closeTag';
    final out = <ContentBlock>[];
    if (escaped.firstOrNull case final TextBlock first) {
      out.add(TextBlock('$open${first.text}'));
      out.addAll(escaped.skip(1));
    } else {
      out
        ..add(TextBlock(open))
        ..addAll(escaped);
    }
    if (out.last is TextBlock) {
      out.last = TextBlock('${(out.last as TextBlock).text}$close');
    } else {
      out.add(const TextBlock(close));
    }
    return out;
  }
}
