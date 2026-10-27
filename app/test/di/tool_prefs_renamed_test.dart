import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/preference_models.dart';

void main() {
  test('renamed nimmt Stufe und altes „immer bestätigen“ mit', () {
    const p = ToolPrefs(
      alwaysConfirm: {'a', 'x'},
      levels: {'a': 'c', 'b': 'z'},
    );
    final r = p.renamed('a', 'b');
    expect(r.levels, {'b': 'c'});
    expect(r.alwaysConfirm, {'x'});
    // Nur „immer bestätigen“ wird zur Stufe D unter dem neuen Namen.
    expect(p.renamed('x', 'y').levelOf('y'), 'd');
    expect(p.renamed('x', 'y').levelOf('x'), isNull);
    // Ohne Eintrag bleibt alles, wie es war (auch ein Eintrag des Ziels).
    const q = ToolPrefs(levels: {'b': 'a'});
    expect(q.renamed('a', 'b'), same(q));
    expect(q.renamed('b', 'b'), same(q));
  });
}
