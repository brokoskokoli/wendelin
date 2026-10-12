import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

void main() {
  final calc = CostCalculator(ModelCatalog.builtIn());

  group('CostCalculator.costMicros (Tabelle, Mikro-USD)', () {
    // Prices in USD/MTok = micro-USD per token.
    for (final (model, usage, expected, why) in [
      (
        'claude-sonnet-5-5',
        const Usage(inputTokens: 1000000),
        2000000,
        '1 M Input à 2 \$',
      ),
      (
        'claude-sonnet-5-5',
        const Usage(outputTokens: 1000),
        10000,
        '1000 Output à 10 \$/M',
      ),
      (
        'claude-sonnet-5-5',
        const Usage(cachedInputTokens: 10000),
        2000,
        'Cache-Read à 0,20 \$/M',
      ),
      (
        'claude-sonnet-5-5',
        const Usage(cacheWriteTokens: 10000),
        25000,
        'Cache-Write à 2,50 \$/M (1,25 × Input)',
      ),
      (
        'claude-opus-5-5',
        const Usage(
          inputTokens: 1200,
          outputTokens: 350,
          cachedInputTokens: 50000,
          cacheWriteTokens: 4000,
        ),
        4800 + 7000 + 10000 + 20000,
        'alle vier Zähler',
      ),
      (
        'claude-fable-5-1',
        const Usage(cachedInputTokens: 100000),
        25000,
        'Fable 5.1 Cache-Read 0,25 \$/M',
      ),
      (
        'claude-haiku-5-5',
        const Usage(inputTokens: 1000, outputTokens: 1000),
        600,
        'Haiku 5.5 bis 100k: 0,10/0,50',
      ),
      (
        'claude-haiku-5-5',
        const Usage(inputTokens: 100000, outputTokens: 1000),
        10500,
        'genau an der Schwelle: noch Standardpreis',
      ),
      (
        'claude-haiku-5-5',
        const Usage(
          inputTokens: 1000,
          cachedInputTokens: 99001,
          outputTokens: 1000,
        ),
        500 + 4950 + 2500,
        'über 100k inkl. Cache: Langkontext-Preis',
      ),
      (
        'claude-haiku-4-5-20251001',
        const Usage(inputTokens: 1000, cacheWriteTokens: 1000),
        1000 + 1250,
        'datiertes Modell → Präfix',
      ),
      (
        'gpt-4.1-nano',
        const Usage(inputTokens: 226, outputTokens: 9, cachedInputTokens: 1024),
        // 22.6 + 3.6 + 25.6 = 51.8 → 52
        52,
        'OpenAI mit Cache-Anteil, gerundet',
      ),
      (
        'openai/gpt-5-mini',
        const Usage(inputTokens: 2, outputTokens: 1),
        3,
        'Anbieter-Präfix, 0,5 + 2 = 2,5 → 3 (kaufmännisch)',
      ),
      ('gpt-5-nano', const Usage(inputTokens: 9), 0, '0,45 → 0'),
      ('claude-sonnet-5-5', Usage.zero, 0, 'nichts verbraucht'),
    ]) {
      test('$model: $why', () {
        expect(calc.costMicros(model, usage), expected);
      });
    }

    test('unbekanntes Modell → null (nicht 0)', () {
      expect(calc.costMicros('mystery-1', const Usage(inputTokens: 5)), isNull);
    });

    test('große Mengen ohne Überlauf', () {
      expect(
        calc.costMicros(
          'claude-fable-5-1',
          const Usage(inputTokens: 1000000000, outputTokens: 100000000),
        ),
        10000000000 + 5000000000,
      );
    });
  });
}
