import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

void main() {
  final catalog = ModelCatalog.builtIn();

  group('ModelCatalog', () {
    test('enthält aktuelle Claude-Modelle mit Preisen', () {
      for (final id in [
        'claude-haiku-5-5',
        'claude-sonnet-5-5',
        'claude-opus-5-5',
        'claude-fable-5-1',
      ]) {
        expect(catalog.lookup(id), isNotNull, reason: id);
      }
      final opus = catalog.lookup('claude-opus-5-5')!;
      expect(
        opus.price,
        ModelPrice.usd(input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5),
      );
      expect(opus.displayName, 'Claude Opus 5.5');
      expect(catalog.lookup('gpt-4.1-nano')!.displayName, 'gpt-4.1-nano');
    });

    test('lookup: exakt, ohne Präfix, längster Präfix, sonst null', () {
      expect(catalog.lookup('claude-opus-5')!.id, 'claude-opus-5');
      expect(catalog.lookup('claude-opus-5-5')!.id, 'claude-opus-5-5');
      expect(catalog.lookup('claude-opus-5-5-20261001')!.id, 'claude-opus-5-5');
      expect(
        catalog.lookup('anthropic/claude-sonnet-5-5')!.id,
        'claude-sonnet-5-5',
      );
      expect(catalog.lookup('openai/gpt-4.1-mini-2025')!.id, 'gpt-4.1-mini');
      expect(catalog.lookup('gpt-4.1x'), isNull);
      expect(catalog.lookup('claude-opus-55'), isNull);
    });

    test('priceFor wählt Langkontext erst über der Schwelle', () {
      final haiku = catalog.lookup('claude-haiku-5-5')!;
      expect(haiku.priceFor(100000), haiku.price);
      expect(haiku.priceFor(100001), haiku.longContextPrice);
      final sonnet = catalog.lookup('claude-sonnet-5-5')!;
      expect(sonnet.priceFor(900000), sonnet.price);
    });

    test('mergeJson überschreibt Felder einzeln und ergänzt Modelle', () {
      final merged = catalog.mergeJson(
        jsonEncode({
          'models': {
            'claude-sonnet-5-5': {'output': 12, 'displayName': 'Sonnet'},
            'z-ai/glm-5.3-flash': {
              'input': 0.15,
              'output': 0.5,
              'cacheRead': 0.03,
              'contextWindow': 1048576,
              'supportsVision': false,
            },
            'claude-haiku-5-5': {'longContextOutput': 3},
          },
        }),
      );
      final sonnet = merged.lookup('claude-sonnet-5-5')!;
      expect(sonnet.price.output, 12000000);
      expect(sonnet.price.input, 2000000);
      expect(sonnet.displayName, 'Sonnet');
      expect(sonnet.contextWindow, 1000000);
      final glm = merged.lookup('z-ai/glm-5.3-flash')!;
      expect(
        glm.price,
        ModelPrice.usd(input: 0.15, output: 0.5, cacheRead: 0.03),
      );
      expect(glm.contextWindow, 1048576);
      expect(glm.supportsVision, isFalse);
      final haiku = merged.lookup('claude-haiku-5-5')!;
      expect(haiku.longContextPrice!.output, 3000000);
      expect(haiku.longContextPrice!.input, 500000);
      expect(haiku.longContextThreshold, 100000);
      // Original bleibt unverändert.
      expect(catalog.lookup('claude-sonnet-5-5')!.price.output, 10000000);
      expect(
        CostCalculator(
          merged,
        ).costMicros('z-ai/glm-5.3-flash', const Usage(inputTokens: 1000000)),
        150000,
      );
    });

    test('mergeJson: Langkontext für Modell ohne Stufe', () {
      final merged = catalog.mergeJson(
        '{"models":{"gpt-4.1":{"longContextThreshold":1000,"longContextInput":4}}}',
      );
      final e = merged.lookup('gpt-4.1')!;
      expect(e.priceFor(1001).input, 4000000);
      expect(e.priceFor(1001).output, 8000000);
    });

    test('mergeJson: Fehler', () {
      for (final bad in [
        '[]',
        '{"modelle":{}}',
        '{"models":{"x":3}}',
        '{"models":{"neu":{"input":1}}}',
        'kein json',
      ]) {
        expect(
          () => catalog.mergeJson(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('toJson ist wieder einlesbar (Roundtrip)', () {
      final json = catalog.toJson();
      final again = ModelCatalog([]).mergeJson(json);
      for (final e in catalog.entries) {
        final r = again.lookup(e.id)!;
        expect(r.price, e.price, reason: e.id);
        expect(r.displayName, e.displayName);
        expect(r.contextWindow, e.contextWindow);
        expect(r.supportsVision, e.supportsVision);
        expect(r.supportsSampling, e.supportsSampling);
        expect(r.supportsForcedToolChoice, e.supportsForcedToolChoice);
        expect(r.longContextThreshold, e.longContextThreshold);
        expect(r.longContextPrice, e.longContextPrice);
      }
    });

    test('ModelPrice: Gleichheit, toString', () {
      final a = ModelPrice.usd(input: 1, output: 2);
      expect(a, const ModelPrice(input: 1000000, output: 2000000));
      expect(
        a.hashCode,
        const ModelPrice(input: 1000000, output: 2000000).hashCode,
      );
      expect(a, isNot(ModelPrice.usd(input: 1, output: 2, cacheRead: 0.1)));
      expect(a.toString(), contains('1000000'));
      expect(catalog.entries.first.toString(), contains('claude'));
    });
  });
}
