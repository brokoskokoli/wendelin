import 'bpe_encoder.dart';

/// Default hotword score of the Parakeet decoder (WP102: 3.0 made the name
/// „Wendelin“ come out right; lower scores cost less on other sentences).
const defaultHotwordsScore = 3.0;

/// The hotwords file for sherpa-onnx (`hotwordsFile`, with
/// `modelingUnit: 'bpe'` and `bpeVocab` from [buildBpeVocab]): one name per
/// line as text, sherpa encodes it with the BPE vocabulary itself.
///
/// Names the vocabulary cannot spell (a character outside `tokens.txt`) and
/// duplicates are left out, so they never reach the native decoder. Returns
/// an empty string if nothing is left.
///
/// (Measured in WP103: a file of pre-tokenized pieces like `▁W end el in`
/// has no effect in sherpa-onnx 1.13.8, text lines do.)
///
/// [terms] must be names only (see `collectHintTerms`).
String buildHotwordsFile(Iterable<String> terms, BpeEncoder encoder) {
  final lines = <String>{};
  for (final term in terms) {
    final name = term.trim().replaceAll(RegExp(r'\s+'), ' ');
    final pieces = encoder.encode(name);
    if (pieces == null || pieces.isEmpty) continue;
    lines.add(name);
  }
  return lines.isEmpty ? '' : '${lines.join('\n')}\n';
}

/// The `bpe_vocab` file sherpa-onnx needs next to `tokens.txt` for hotwords
/// ("piece<TAB>score" per line; the sherpa package ships none). Derived
/// from `tokens.txt`: control tokens score 0, the others the negated
/// distance of their id from the first regular piece (the SentencePiece
/// merge order of the NeMo tokenizer, equal to the `tokenizer.vocab` of the
/// `.nemo` file); `<blk>` is not part of the BPE model.
String buildBpeVocab(String tokensTxt) {
  final rows = <(String, int)>[];
  for (final line in tokensTxt.split('\n')) {
    final cut = line.lastIndexOf(' ');
    if (cut <= 0) continue;
    final id = int.tryParse(line.substring(cut + 1).trim());
    final piece = line.substring(0, cut);
    if (id == null || piece == '<blk>') continue;
    rows.add((piece, id));
  }
  final first = rows
      .where((r) => !BpeEncoder.isControl(r.$1))
      .map((r) => r.$2)
      .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
  final out = StringBuffer();
  for (final (piece, id) in rows) {
    final score = BpeEncoder.isControl(piece) || first == null ? 0 : first - id;
    out.write('$piece\t$score\n');
  }
  return out.toString();
}
