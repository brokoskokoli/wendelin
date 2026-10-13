/// A line-based diff of [before] and [after] for the confirmation card:
/// removed lines start with `- `, added ones with `+ `, unchanged ones with
/// two spaces. Runs of more than [context] × 2 unchanged lines are
/// shortened to `  …`; at most [maxLines] lines are returned (the rest is
/// counted in a last line).
String lineDiff(
  List<String> before,
  List<String> after, {
  int context = 1,
  int maxLines = 40,
}) {
  final n = before.length;
  final m = after.length;
  // Längste gemeinsame Teilfolge (Abschnitte sind klein; begrenzt durch die
  // Aufrufer).
  final lcs = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = before[i] == after[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final ops = <(String, String)>[];
  var i = 0;
  var j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && before[i] == after[j]) {
      ops.add((' ', before[i]));
      i++;
      j++;
    } else if (i < n && (j == m || lcs[i + 1][j] >= lcs[i][j + 1])) {
      ops.add(('-', before[i]));
      i++;
    } else {
      ops.add(('+', after[j]));
      j++;
    }
  }
  final out = <String>[];
  for (var k = 0; k < ops.length; k++) {
    final (op, text) = ops[k];
    if (op != ' ') {
      out.add('$op $text');
      continue;
    }
    var end = k;
    while (end < ops.length && ops[end].$1 == ' ') {
      end++;
    }
    final run = end - k;
    final lead = k == 0 ? 0 : context;
    final trail = end == ops.length ? 0 : context;
    if (run <= lead + trail + 1) {
      for (var x = k; x < end; x++) {
        out.add('  ${ops[x].$2}');
      }
    } else {
      for (var x = k; x < k + lead; x++) {
        out.add('  ${ops[x].$2}');
      }
      out.add('  …');
      for (var x = end - trail; x < end; x++) {
        out.add('  ${ops[x].$2}');
      }
    }
    k = end - 1;
  }
  if (out.length <= maxLines) return out.join('\n');
  return [
    ...out.take(maxLines),
    '… (${out.length - maxLines} weitere Zeilen)',
  ].join('\n');
}
