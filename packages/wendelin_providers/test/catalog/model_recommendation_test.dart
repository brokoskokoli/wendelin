import 'package:test/test.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

void main() {
  test('jede Empfehlung gehört zu einer Vorlage', () {
    final ids = {for (final t in providerTemplates) t.id};
    expect(modelRecommendations.keys, isNotEmpty);
    for (final id in modelRecommendations.keys) {
      expect(ids, contains(id));
      expect(providerTemplateById(id)!.recommendations, isNotEmpty);
    }
  });

  test('Empfehlungen sind plausibel und die Vorbelegung ist empfohlen', () {
    for (final t in providerTemplates) {
      for (final r in t.recommendations) {
        expect(r.modelId, isNotEmpty);
        expect(r.hits, inInclusiveRange(0, r.runs));
        expect(r.p50Seconds, greaterThan(0));
        expect(r.measured, matches(r'^\d{4}-\d{2}-\d{2}$'));
      }
      if (t.recommendations.isNotEmpty) {
        expect(t.suggestedModel, t.recommendations.first.modelId, reason: t.id);
      }
    }
  });

  test('nicht gemessene Vorlagen empfehlen nichts', () {
    for (final id in ['mistral', 'openrouter', 'ollama', 'custom']) {
      expect(providerTemplateById(id)!.recommendations, isEmpty, reason: id);
    }
  });

  test('NEAR ist ehrlich als schwächer gekennzeichnet, die anderen nicht', () {
    expect(
      providerTemplateById('near')!.recommendations.single.weakerThanTee,
      isTrue,
    );
    for (final id in ['claude', 'openai', 'phala', 'tinfoil']) {
      expect(
        providerTemplateById(id)!.recommendations.single.weakerThanTee,
        isFalse,
      );
    }
  });
}
