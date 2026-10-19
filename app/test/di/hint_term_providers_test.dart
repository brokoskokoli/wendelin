import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/hint_term_providers.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  test('Listennamen und Aliase werden zu Namen, Inhalte fallen weg', () async {
    final terms = await collectHintTerms([
      ListNameHintSource(
        () => [
          'Einkaufen',
          'Einkaufsliste',
          // What a careless source could hand over: content, not a name.
          'Ruf morgen Frau Meier wegen der Rechnung an',
          'Milch, Eier und Brot kaufen',
        ],
      ),
    ]);
    expect(terms, ['Einkaufen', 'Einkaufsliste']);
  });

  test('Quelle liefert Namen der Art „Liste“', () async {
    final terms = await const ListNameHintSource(_names).terms();
    expect(terms.single.kind, HintTermKind.list);
  });
}

Iterable<String> _names() => ['Einkaufen'];
