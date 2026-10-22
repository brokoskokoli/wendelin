import 'package:test/test.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/src/common/port_exception.dart';
import 'package:wendelin_integrations/src/home_assistant/ha_context.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

// Made-up flat: names do not contain the type word the user says.
const _flat = [
  HaEntity(
    entityId: 'light.living_main',
    name: 'Licht Wohnzimmer',
    area: 'Wohnzimmer',
  ),
  HaEntity(
    entityId: 'light.bedroom',
    name: 'Schlafzimmer Deckenlicht',
    area: 'Schlafzimmer',
  ),
  HaEntity(
    entityId: 'cover.living',
    name: 'Terrasse links',
    area: 'Wohnzimmer',
  ),
  HaEntity(entityId: 'cover.office', name: 'Fenster Süd', area: 'Büro'),
  HaEntity(entityId: 'cover.office2', name: 'Fenster Nord', area: 'Büro'),
  HaEntity(entityId: 'switch.plug', name: 'Kaffeemaschine', area: 'Küche'),
  HaEntity(
    entityId: 'climate.living',
    name: 'Thermostat Wohnzimmer',
    area: 'Wohnzimmer',
  ),
  HaEntity(entityId: 'lock.front', name: 'Haustür', area: 'Flur'),
];

void main() {
  late HaContext ctx;
  setUp(() {
    ctx = HaContext(FakeHaApi(), FakeHaEntityStore(_flat));
  });

  Future<String> id(String q) async => (await ctx.resolve(q)).entityId;
  Future<String> failure(String q) async {
    try {
      await ctx.resolve(q);
    } on PortException catch (e) {
      return '${e.kind.name}: ${e.message}';
    }
    return 'kein Fehler';
  }

  group('Typ und Raum (WP135 B)', () {
    test('„Lampe Wohnzimmer“ trifft das einzige Licht im Raum', () async {
      expect(await id('Lampe Wohnzimmer'), 'light.living_main');
      expect(await id('Leuchte im Wohnzimmer'), 'light.living_main');
      expect(await id('Wohnzimmer Lampe'), 'light.living_main');
    });

    test(
      'Rollo-Wörter, auch Verhörer („Rolle“), und andere Sprachen',
      () async {
        expect(await id('Rollo Wohnzimmer'), 'cover.living');
        expect(await id('Rolladen Wohnzimmer'), 'cover.living');
        expect(await id('Rolle Wohnzimmer'), 'cover.living');
        expect(await id('Jalousie im Wohnzimmer'), 'cover.living');
        expect(await id('Wohnzimmer blinds'), 'cover.living');
        expect(await id('Volet Wohnzimmer'), 'cover.living');
      },
    );

    test('Steckdose und Heizung nach Typ und Raum', () async {
      expect(await id('Steckdose Küche'), 'switch.plug');
      expect(await id('Heizung Wohnzimmer'), 'climate.living');
    });

    test('nur der Typ: ein einziges Gerät genügt', () async {
      expect(await id('die Steckdose'), 'switch.plug');
      expect(await id('Heizung'), 'climate.living');
    });

    test('mehrere Treffer bleiben mehrdeutig', () async {
      final r = await failure('Rollo Büro');
      expect(r, startsWith('rejected: Mehrdeutig'));
      expect(r, contains('Fenster Süd'));
      expect(r, contains('Fenster Nord'));
      // Nur Typ, mehrere Geräte des Typs.
      expect(await failure('Lampe'), startsWith('rejected: Mehrdeutig'));
      expect(await failure('Rollo'), startsWith('rejected: Mehrdeutig'));
    });

    test('anderer Raum oder Typ ohne Gerät: nicht gefunden', () async {
      expect(await failure('Lampe Keller'), startsWith('notFound'));
      expect(await failure('Lampe Büro'), startsWith('notFound'));
      expect(await failure('Rollo Flur'), startsWith('notFound'));
    });

    test('Typ eines anderen Gerätes nimmt nie ein Schloss mit', () async {
      // „Tür“ ist kein Typwort: kein Treffer über den Raum.
      expect(await failure('Lampe Flur'), startsWith('notFound'));
    });

    test('Name vor Typ: ein passender Name gewinnt', () async {
      expect(await id('Schlafzimmer Deckenlicht'), 'light.bedroom');
      expect(await id('Terrasse links'), 'cover.living');
      expect(await id('light.living_main'), 'light.living_main');
    });

    test('ohne Typwort bleibt es beim Namens- und Raumabgleich', () async {
      expect(await failure('Wohnzimmer'), startsWith('rejected: Mehrdeutig'));
      expect(await failure('Keller'), startsWith('notFound'));
    });
  });
}
