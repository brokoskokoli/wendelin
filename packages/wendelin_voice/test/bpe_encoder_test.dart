import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  // The fixture is the real Parakeet tokens.txt reduced to the pieces these
  // names need (real ids). Expected pieces: SentencePiece with the model
  // `bpe.model` of nvidia/parakeet-tdt-0.6b-v3 (WP103, venv of WP102).
  final encoder = BpeEncoder.fromTokens(
    File('test/fixtures/parakeet_tokens_subset.txt').readAsStringSync(),
  );
  const golden = {
    'Wendelin': ['▁W', 'end', 'el', 'in'],
    'Wendelin-Test': ['▁W', 'end', 'el', 'in', '-', 'T', 'est'],
    'Küche': ['▁K', 'ü', 'che'],
    'Gästezimmer': ['▁G', 'ä', 'ste', 'z', 'im', 'mer'],
    'Einkaufsliste': ['▁Ein', 'ka', 'u', 'fs', 'l', 'iste'],
    'Jürgen': ['▁J', 'ür', 'gen'],
    'Stefan Richter': ['▁Ste', 'f', 'an', '▁Rich', 'ter'],
    'Wohnzimmer Licht': ['▁Wo', 'hn', 'z', 'im', 'mer', '▁Li', 'cht'],
    'Édouard': ['▁É', 'd', 'ou', 'ard'],
    'Zoë': ['▁Z', 'o', 'ë'],
    'Hélène': ['▁H', 'él', 'è', 'ne'],
    'Bücherregal': ['▁B', 'ü', 'cher', 're', 'gal'],
  };

  for (final MapEntry(:key, :value) in golden.entries) {
    test('$key wie SentencePiece', () => expect(encoder.encode(key), value));
  }

  test('niedrigste Id gewinnt, nicht die längste Verschmelzung', () {
    // „end“ (kleine Id) muss vor „Wend“-artigen Verschmelzungen kommen;
    // eine Umkehr der Rangfolge ergäbe andere Stücke.
    final e = BpeEncoder.fromTokens('▁a 0\n▁ab 1\nb 2\nc 3\nbc 4\n');
    expect(e.encode('abc'), ['▁ab', 'c']);
    final f = BpeEncoder.fromTokens('▁a 0\n▁ab 9\nb 2\nc 3\nbc 1\n');
    expect(f.encode('abc'), ['▁a', 'bc']);
  });

  test('Leerraum wird zusammengefasst, Wortgrenzen bleiben getrennt', () {
    expect(encoder.encode('  Stefan \n Richter '), golden['Stefan Richter']);
    expect(encoder.encode(''), isEmpty);
  });

  test('unbekanntes Zeichen: kein Hotword (null)', () {
    expect(encoder.encode('Wendelin 🚀'), isNull);
  });

  test('Steuertokens werden nie verschmolzen', () {
    final e = BpeEncoder.fromTokens(
      '▁ 0\n< 1\nu 2\nn 3\nk 4\n> 5\n<unk> 6\n<blk> 7\n',
    );
    expect(e.encode('<unk>'), ['▁', '<', 'u', 'n', 'k', '>']);
    expect(e.vocabularySize, 6);
  });

  group('Hotwords-Datei', () {
    test('eine Zeile je Name als Text', () {
      expect(
        buildHotwordsFile(['Wendelin', ' Küche  ', 'Stefan Richter'], encoder),
        'Wendelin\nKüche\nStefan Richter\n',
      );
    });

    test('unbekannte Zeichen und Doppelte entfallen', () {
      expect(
        buildHotwordsFile(['Zoë', 'Zoë', 'Zoë 🚀', ' '], encoder),
        'Zoë\n',
      );
      expect(buildHotwordsFile(const [], encoder), '');
    });
  });

  group('bpe_vocab aus tokens.txt', () {
    test('Steuertokens 0, übrige negierter Abstand zum ersten Stück', () {
      const tokens = '<unk> 0\n<|pnc|> 1\nen 2\n▁s 3\n<blk> 4\n';
      expect(buildBpeVocab(tokens), '<unk>\t0\n<|pnc|>\t0\nen\t0\n▁s\t-1\n');
    });

    test('echtes Fixture: Reihenfolge der Ids bleibt als Rang erhalten', () {
      final vocab = buildBpeVocab(
        File('test/fixtures/parakeet_tokens_subset.txt').readAsStringSync(),
      );
      final rows = [for (final l in vocab.trim().split('\n')) l.split('\t')];
      expect(rows.every((r) => r.length == 2), isTrue);
      expect(rows.any((r) => r[0] == '<blk>'), isFalse);
      // Kleinere Id = höherer Rang = größerer Score („end“ hat eine kleinere
      // Id als „▁W“).
      int score(String p) => int.parse(rows.firstWhere((r) => r[0] == p)[1]);
      expect(score('end'), greaterThan(score('▁W')));
    });
  });
}
