/// SentencePiece-BPE encoder for the vocabulary of a sherpa-onnx
/// `tokens.txt` (WP103): turns names into the token sequences of the
/// pre-tokenized hotwords file (Parakeet TDT is a SentencePiece-BPE model).
///
/// Pure Dart, no native code. It reproduces SentencePiece for text without
/// byte fallback: a dummy prefix `▁`, spaces as `▁`, then repeated merging
/// of the adjacent pair whose joined piece exists and has the best score.
/// In the NeMo tokenizers the score is the negated token id, so the lowest
/// id wins; ties go to the leftmost pair.
final class BpeEncoder {
  BpeEncoder._(this._ids);

  /// Reads `tokens.txt` ("piece id" per line, id from the last space).
  /// Control tokens (`<unk>`, `<|…|>`, `<blk>`, `<0x..>`) are never merged.
  factory BpeEncoder.fromTokens(String tokensTxt) {
    final ids = <String, int>{};
    for (final line in tokensTxt.split('\n')) {
      final cut = line.lastIndexOf(' ');
      if (cut <= 0) continue;
      final id = int.tryParse(line.substring(cut + 1).trim());
      final piece = line.substring(0, cut);
      if (id == null || isControl(piece)) continue;
      ids[piece] = id;
    }
    return BpeEncoder._(ids);
  }

  /// SentencePiece word boundary.
  static const wordStart = '▁';

  final Map<String, int> _ids;

  /// Whether [piece] is a control token (`<unk>`, `<|…|>`), never merged.
  static bool isControl(String piece) =>
      piece.length > 2 && piece.startsWith('<') && piece.endsWith('>');

  /// Number of known pieces.
  int get vocabularySize => _ids.length;

  /// The pieces of [text], or `null` if a character is not in the
  /// vocabulary (the term cannot be a hotword then). Empty text gives an
  /// empty list.
  List<String>? encode(String text) {
    final words = text.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return const [];
    final symbols = [
      for (final word in words)
        ...'$wordStart$word'.runes.map(String.fromCharCode),
    ];
    // A piece never crosses a word start, so every word merges on its own.
    final out = <String>[];
    var from = 0;
    for (var i = 1; i <= symbols.length; i++) {
      if (i == symbols.length || symbols[i] == wordStart) {
        // A literal „▁“ inside a word is not a boundary in the input.
        out.addAll(_merge(symbols.sublist(from, i)));
        from = i;
      }
    }
    return out.every(_ids.containsKey) ? out : null;
  }

  List<String> _merge(List<String> symbols) {
    final s = [...symbols];
    while (s.length > 1) {
      var best = -1;
      var bestId = 1 << 62;
      for (var i = 0; i + 1 < s.length; i++) {
        final id = _ids['${s[i]}${s[i + 1]}'];
        if (id != null && id < bestId) {
          best = i;
          bestId = id;
        }
      }
      if (best < 0) break;
      s.replaceRange(best, best + 2, ['${s[best]}${s[best + 1]}']);
    }
    return s;
  }
}
