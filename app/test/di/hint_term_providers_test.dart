import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/core_providers.dart';
import 'package:wendelin/di/hint_term_providers.dart';
import 'package:wendelin/di/home_assistant.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  _moreSources();
  _providers();
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

class _Contacts extends Notifier<List<String>> {
  @override
  List<String> build() => const [];
  void set(List<String> next) => state = next;
}

final _contactState = NotifierProvider<_Contacts, List<String>>(_Contacts.new);

void _providers() {
  group('hintTermsProvider', () {
    late SecretStoreHa ha;
    late ProviderContainer c;

    setUp(() {
      ha = SecretStoreHa(InMemorySecretStore());
      c = ProviderContainer(
        overrides: [
          startupProvider.overrideWithValue(
            StartupSettings(
              lists: [
                ListDefinition(
                  id: 'a',
                  name: 'Einkaufen',
                  target: 't',
                  aliases: ['Einkaufsliste', 'Milch, Eier und Brot kaufen'],
                ),
              ],
            ),
          ),
          haStoreProvider.overrideWithValue(ha),
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
          contactNamesProvider.overrideWith(
            (ref) =>
                () async => ref.watch(_contactState),
          ),
        ],
      );
      addTearDown(c.dispose);
    });

    test(
      'Listen, HA und Kontakte als Namen; ein Inhaltssatz fällt weg',
      () async {
        await ha.save(const [
          HaEntity(entityId: 'light.k', name: 'Deckenlicht', area: 'Küche'),
          HaEntity(entityId: 'sensor.x', name: 'Ist an, 21 Grad warm.'),
        ]);
        c.read(_contactState.notifier).set(['Anna Meier']);
        final terms = await c.read(hintTermsProvider.future);
        expect(
          terms,
          unorderedEquals([
            'Wendelin',
            'Anna Meier',
            'Einkaufen',
            'Einkaufsliste',
            'Küche',
            'Deckenlicht',
          ]),
        );
      },
    );

    Future<List<String>> next() async {
      await Future<void>.delayed(Duration.zero);
      return c.read(hintTermsProvider.future);
    }

    test('Neuberechnung bei Listen, HA-Freigaben und Kontakten', () async {
      expect(await c.read(hintTermsProvider.future), contains('Einkaufen'));
      c.listen(hintTermsProvider, (_, _) {});

      // ignore: invalid_use_of_protected_member
      c.read(listDefinitionsProvider.notifier).state = [
        ListDefinition(id: 'b', name: 'Baumarkt', target: 't'),
      ];
      var t = await next();
      expect(t, contains('Baumarkt'));
      expect(t, isNot(contains('Einkaufen')));

      await ha.save(const [HaEntity(entityId: 'l.1', name: 'Stehlampe')]);
      c.invalidate(haApprovedEntitiesProvider);
      t = await next();
      expect(t, contains('Stehlampe'));

      c.read(_contactState.notifier).set(['Berta']);
      t = await next();
      expect(t, contains('Berta'));
    });

    test(
      'ohne Invalidate der Freigaben bleibt der Stand (Beleg des Auslösers)',
      () async {
        await c.read(hintTermsProvider.future);
        c.listen(hintTermsProvider, (_, _) {});
        await ha.save(const [HaEntity(entityId: 'l.1', name: 'Stehlampe')]);
        expect(await next(), isNot(contains('Stehlampe')));
      },
    );
  });
}
