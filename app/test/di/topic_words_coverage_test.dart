import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/integrations/registry.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  test('jede eingebaute Integration hat Themenwörter in jeder Sprache', () {
    final ids = [for (final s in builtInIntegrationSpecs) s.id];
    expect(ids, isNotEmpty);
    for (final MapEntry(:key, :value) in topicWordsByLanguage.entries) {
      expect(
        ids.where((id) => (value[id] ?? const []).isEmpty),
        isEmpty,
        reason: 'Sprache $key',
      );
    }
  });
}
