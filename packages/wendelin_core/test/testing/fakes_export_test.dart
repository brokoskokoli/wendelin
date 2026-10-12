import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// fakes.dart may be used by production code and must not pull in
/// package:test (directly or through files it exports).
void main() {
  test('fakes.dart exports the fakes', () {
    expect(FakeLlmProvider([]).type, ProviderType.fake);
    expect(FakeTool(name: 'a__b').name, 'a__b');
  });

  test('fakes.dart and its exported files do not import package:test', () {
    final fakes = File('lib/fakes.dart').readAsStringSync();
    final exported = RegExp(r"export '([^']+)'")
        .allMatches(fakes)
        .map((m) => 'lib/${m.group(1)}')
        .toList();
    expect(exported, isNotEmpty);
    for (final path in ['lib/fakes.dart', ...exported]) {
      final text = File(path).readAsStringSync();
      expect(text, isNot(contains("import 'package:test")), reason: path);
      expect(text, isNot(contains('_contract.dart')), reason: path);
    }
  });
}
