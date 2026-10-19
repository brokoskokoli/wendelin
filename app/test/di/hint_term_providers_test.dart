import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/hint_term_providers.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  _moreSources();
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

void _moreSources() {
  test('HA-Räume und Entitätsnamen, nie Zustände oder Ids', () async {
    final terms = await const HaNameHintSource(_entities).terms();
    expect(
      terms.map((t) => (t.kind, t.text)),
      containsAll([
        (HintTermKind.room, 'Küche'),
        (HintTermKind.entity, 'Deckenlicht'),
      ]),
    );
    expect(terms.any((t) => t.text.contains('light.')), isFalse);
    // Der Rückschlag: ein Satz als Name fällt beim Sammeln weg.
    final cleaned = await collectHintTerms([
      HaNameHintSource(
        () async => const [
          HaEntity(entityId: 'sensor.x', name: 'Ist an, 21 Grad warm.'),
        ],
      ),
    ]);
    expect(cleaned, isEmpty);
  });

  test('Kontakte: Standard leer, Namen als Art „contact“', () async {
    expect(await const ContactNameHintSource(_noContacts).terms(), isEmpty);
    final terms = await ContactNameHintSource(() async => ['Anna Meier'])
        .terms();
    expect(terms.single.kind, HintTermKind.contact);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(contactNamesProvider)(), isEmpty);
  });
}

Future<List<HaEntity>> _entities() async => const [
  HaEntity(entityId: 'light.k', name: 'Deckenlicht', area: 'Küche'),
];
Future<List<String>> _noContacts() async => const [];

Iterable<String> _names() => ['Einkaufen'];
