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

import '../support/test_env.dart';

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
    // Ohne Freigabe der Integration bleibt die Quelle leer.
    final c = TestEnv().container();
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
            'Lampe',
            'Licht',
          ]),
        );
      },
    );

    test(
      '300 Kontakte verdrängen weder Listen noch HA-Namen (WP191)',
      () async {
        c.read(_contactState.notifier).set([
          for (var i = 0; i < 300; i++) 'Person ${_letters(i)}',
        ]);
        await ha.save([
          for (var i = 0; i < 10; i++)
            HaEntity(
              entityId: 'light.l$i',
              name: 'Lampe ${_letters(i)}',
              area: 'Raum ${_letters(i)}',
            ),
        ]);
        final terms = await c.read(hintTermsProvider.future);
        expect(terms, contains('Einkaufen'));
        expect(terms, contains('Einkaufsliste'));
        for (var i = 0; i < 10; i++) {
          expect(terms, contains('Lampe ${_letters(i)}'));
          expect(terms, contains('Raum ${_letters(i)}'));
        }
        expect(terms, hasLength(64));
      },
    );

    Future<List<String>> next() async {
      await Future<void>.delayed(Duration.zero);
      return c.read(hintTermsProvider.future);
    }

    group('Synonyme (WP191)', () {
      Future<List<String>> termsFor(
        List<HaEntity> entities, {
        String? language,
      }) async {
        await ha.save(entities);
        if (language != null) {
          c.read(languageProvider.notifier).state = language;
        }
        return c.read(hintTermsProvider.future);
      }

      const light = HaEntity(entityId: 'light.k', name: 'Deckenlicht');
      const cover = HaEntity(entityId: 'cover.w', name: 'Terrasse');

      test('nur Domains vorhandener Entitäten, de', () async {
        final t = await termsFor([light], language: 'de');
        expect(t, containsAll(['Lampe', 'Licht']));
        expect(t, isNot(contains('Rollo')));
        expect(t, isNot(contains('Ventilator')));
      });

      test('ohne Entitäten keine Synonyme', () async {
        final t = await termsFor(const [], language: 'de');
        expect(t, isNot(contains('Lampe')));
      });

      test('Sprache en und fr; unbekannt fällt auf en', () async {
        expect(
          await termsFor([light, cover], language: 'fr'),
          containsAll(['lampe', 'volet']),
        );
        c.invalidate(hintTermsProvider);
        c.read(languageProvider.notifier).state = 'en';
        final en = await c.read(hintTermsProvider.future);
        expect(en, containsAll(['lamp', 'blind']));
        expect(en, isNot(contains('lampe')));
        c.read(languageProvider.notifier).state = 'xx';
        expect(await next(), containsAll(['lamp', 'blind']));
      });

      test('Sprachwechsel berechnet die Begriffe neu', () async {
        await termsFor([light], language: 'de');
        c.listen(hintTermsProvider, (_, _) {});
        c.read(languageProvider.notifier).state = 'en';
        final t = await next();
        expect(t, contains('lamp'));
        expect(t, isNot(contains('Lampe')));
      });

      test('Entitätsname gleich Synonym: nur einmal', () async {
        final t = await termsFor([
          const HaEntity(entityId: 'light.x', name: 'Lampe'),
        ], language: 'de');
        expect(t.where((e) => e.toLowerCase() == 'lampe'), hasLength(1));
      });
    });

    test('Log nennt nur Zahlen je Art, keine Namen', () async {
      final lines = <String>[];
      final old = hintTermLog;
      hintTermLog = lines.add;
      addTearDown(() => hintTermLog = old);
      await ha.save(const [
        HaEntity(entityId: 'light.k', name: 'Geheimlicht', area: 'Geheimraum'),
      ]);
      c.read(_contactState.notifier).set(['Geheime Person']);
      await c.read(hintTermsProvider.future);
      expect(lines, hasLength(1));
      expect(
        lines.single,
        'Hinweisbegriffe: agent=1 list=2 room=1 entity=1 synonym=2 contact=1',
      );
      for (final n in ['Geheim', 'Einkauf', 'Wendelin', 'Lampe']) {
        expect(lines.single, isNot(contains(n)));
      }
    });

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

/// Letters only (hint names without digits need a letter, a-z, then aa…).
String _letters(int i) => String.fromCharCode(97 + i % 26) * (1 + i ~/ 26);
