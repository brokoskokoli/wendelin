import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/src/home_assistant/ha_context.dart';
import 'package:wendelin_integrations/src/home_assistant/ha_fast_path.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// The fast path without a model (WP135 D): what it recognizes, and above
/// all everything it must hand to the model. Invented device names.
const _devices = [
  HaEntity(entityId: 'light.kitchen', name: 'Küche Deckenlicht', area: 'Küche'),
  HaEntity(
    entityId: 'light.bedroom',
    name: 'Schlafzimmer Licht',
    area: 'Schlafzimmer',
  ),
  HaEntity(
    entityId: 'light.lounge_a',
    name: 'Lounge Stehlampe',
    area: 'Lounge',
  ),
  HaEntity(entityId: 'light.lounge_b', name: 'Lounge Spots', area: 'Lounge'),
  HaEntity(entityId: 'switch.coffee', name: 'Kaffeemaschine', area: 'Küche'),
  HaEntity(
    entityId: 'switch.oven',
    name: 'Backofen',
    area: 'Küche',
    alwaysConfirm: true,
  ),
  HaEntity(
    entityId: 'cover.bay',
    name: 'Rollo Erker',
    area: 'Lounge',
    noConfirm: true,
    deviceClass: 'blind',
  ),
  HaEntity(
    entityId: 'cover.office',
    name: 'Rollo Büro',
    area: 'Büro',
    deviceClass: 'blind',
  ),
  HaEntity(
    entityId: 'cover.garage',
    name: 'Garagentor',
    area: 'Garage',
    noConfirm: true,
    deviceClass: 'garage',
  ),
  HaEntity(
    entityId: 'cover.noclass',
    name: 'Markise Terrasse',
    area: 'Terrasse',
    noConfirm: true,
  ),
  HaEntity(entityId: 'climate.lounge', name: 'Heizung Lounge', area: 'Lounge'),
  HaEntity(entityId: 'lock.front', name: 'Haustür', area: 'Flur'),
  HaEntity(entityId: 'scene.movie', name: 'Filmabend', area: 'Lounge'),
  HaEntity(entityId: 'media_player.tv', name: 'Fernseher', area: 'Lounge'),
  HaEntity(entityId: 'light.attic', name: 'Attic Lamp', area: 'Attic'),
  HaEntity(
    entityId: 'cover.attic',
    name: 'Attic Blind',
    area: 'Attic',
    noConfirm: true,
    deviceClass: 'blind',
  ),
  HaEntity(entityId: 'light.cave', name: 'Cave Plafonnier', area: 'Cave'),
  HaEntity(
    entityId: 'cover.mansarde',
    name: 'Volet Mansarde',
    area: 'Mansarde',
    noConfirm: true,
    deviceClass: 'shutter',
  ),
  HaEntity(
    entityId: 'light.gone',
    name: 'Keller Funzel',
    area: 'Keller',
    missing: true,
  ),
];

void main() {
  late HaFastPath fast;

  setUp(() {
    fast = HaFastPath(HaContext(FakeHaApi(), FakeHaEntityStore(_devices)));
  });

  Future<Map<String, Object?>?> args(String text, [String lang = 'de']) async =>
      (await fast.match(text, language: lang))?.arguments;

  Future<void> expectCall(
    String text,
    String entity,
    String service, {
    String lang = 'de',
    Map<String, Object?> extra = const {},
  }) async {
    final call = await fast.match(text, language: lang);
    expect(call, isNotNull, reason: '$lang: $text');
    expect(call!.tool, 'ha__call');
    expect(call.arguments, {'entity': entity, 'service': service, ...extra});
  }

  group('erkannt', () {
    test('Licht an/aus nach Name, de', () async {
      await expectCall('Küche Deckenlicht aus', 'light.kitchen', 'turn_off');
      await expectCall(
        'Mach bitte das Licht in der Küche an',
        'light.kitchen',
        'turn_on',
      );
      await expectCall(
        'Hey Wendelin, schalte die Lampe im Schlafzimmer aus.',
        'light.bedroom',
        'turn_off',
      );
      await expectCall(
        'Kaffeemaschine einschalten',
        'switch.coffee',
        'turn_on',
      );
    });

    test('Raum plus Typ ohne Namen (Lampe für „Licht“)', () async {
      await expectCall('Schlafzimmer Lampe an', 'light.bedroom', 'turn_on');
    });

    test('Helligkeit in Prozent', () async {
      await expectCall(
        'Küche Licht auf 30 Prozent',
        'light.kitchen',
        'turn_on',
        extra: {'brightness_pct': 30},
      );
      await expectCall(
        'Dimm das Licht in der Küche auf 40 %',
        'light.kitchen',
        'turn_on',
        extra: {'brightness_pct': 40},
      );
    });

    test('Rollo: öffnen, schließen, stoppen, Position, halb', () async {
      await expectCall('Rollo Erker runter', 'cover.bay', 'close_cover');
      await expectCall('Rollo im Erker hoch', 'cover.bay', 'open_cover');
      await expectCall('Rollo Erker stopp', 'cover.bay', 'stop_cover');
      await expectCall(
        'Rollo Erker auf 50 Prozent',
        'cover.bay',
        'set_cover_position',
        extra: {'position_pct': 50},
      );
      await expectCall(
        'Rollo Erker auf halb',
        'cover.bay',
        'set_cover_position',
        extra: {'position_pct': 50},
      );
      // Speech recognition: „Rolle“ for „Rollo“.
      await expectCall('Rolle Erker runter', 'cover.bay', 'close_cover');
    });

    test('Heizung: Temperatur mit Dezimalstelle, an/aus', () async {
      await expectCall(
        'Heizung Lounge auf 21,5 Grad',
        'climate.lounge',
        'set_temperature',
        extra: {'temperature': '21.5'},
      );
      await expectCall('Heizung Lounge aus', 'climate.lounge', 'turn_off');
    });

    test('en und fr', () async {
      await expectCall(
        'Turn the attic lamp off',
        'light.attic',
        'turn_off',
        lang: 'en',
      );
      await expectCall(
        'Please put the attic light on',
        'light.attic',
        'turn_on',
        lang: 'en-US',
      );
      await expectCall(
        'Lower the attic blind',
        'cover.attic',
        'close_cover',
        lang: 'en',
      );
      await expectCall(
        'Set the lounge heating to 20 degrees',
        'climate.lounge',
        'set_temperature',
        lang: 'en',
        extra: {'temperature': '20'},
      );
      await expectCall(
        'Éteins la lumière de la cave',
        'light.cave',
        'turn_off',
        lang: 'fr',
      );
      await expectCall(
        'Ferme le volet de la mansarde',
        'cover.mansarde',
        'close_cover',
        lang: 'fr',
      );
      await expectCall(
        'Mets le volet mansarde à 30 pour cent',
        'cover.mansarde',
        'set_cover_position',
        lang: 'fr',
        extra: {'position_pct': 30},
      );
    });
  });

  group('geht ans Modell', () {
    final cases = <String, String>{
      // Bare type without room or name (decision of the maintainer).
      'Licht an': 'de',
      'Lampe aus': 'de',
      'Rollo runter': 'de',
      'Turn the light on': 'en',
      'Allume la lumière': 'fr',
      // Several lights match.
      'Lounge Lampe an': 'de',
      // Unknown word: negation, question, second request, extra wish.
      'Mach das Licht in der Küche nicht an': 'de',
      'Ist das Licht in der Küche an': 'de',
      'Küche Licht an und Schlafzimmer Licht aus': 'de',
      'Küche Licht an und spiel Musik': 'de',
      'Küche Licht an wenn ich komme': 'de',
      "Don't turn the attic light on": 'en',
      'Ne allume pas la lumière de la cave': 'fr',
      // Two actions / action missing / action not for the type.
      'Küche Licht an aus': 'de',
      'Küche Licht': 'de',
      'Küche Licht runter': 'de',
      'Küche Licht heller': 'de',
      'Kaffeemaschine auf 50 Prozent': 'de',
      'Heizung Lounge an aus': 'de',
      // Wrong or odd numbers.
      'Küche Licht auf 0 Prozent': 'de',
      'Küche Licht auf 150 Prozent': 'de',
      'Küche Licht auf 30': 'de',
      'Heizung Lounge auf 50 Grad': 'de',
      'Heizung Lounge auf 21 Prozent': 'de',
      'Küche Licht auf 30 Grad': 'de',
      'Rollo Erker auf 20 Prozent und 30 Prozent': 'de',
      'Rollo Erker halb auf 30 Prozent': 'de',
      // Devices that never run without the model.
      'Haustür aufschließen': 'de',
      'Flur Haustür auf': 'de',
      'Garagentor auf': 'de',
      'Garagentor runter': 'de',
      'Terrasse Markise ausfahren': 'de',
      'Rollo Büro runter': 'de',
      'Backofen einschalten': 'de',
      'Filmabend an': 'de',
      'Lounge Fernseher aus': 'de',
      'Keller Funzel an': 'de',
      // Not a device of the user / wrong type for the name.
      'Wohnzimmer Licht an': 'de',
      'Küche Rollo runter': 'de',
      'Küche Heizung an': 'de',
      // Empty and unknown language.
      '': 'de',
      '   ': 'de',
    };
    cases.forEach((text, lang) {
      test('"$text" ($lang)', () async {
        expect(await args(text, lang), isNull);
      });
    });

    test('unbekannte Sprache und fehlende Sprache', () async {
      expect(await fast.match('Küche Licht an', language: 'it'), isNull);
      expect(await fast.match('Küche Licht an', language: null), isNull);
      expect(await fast.match('Küche Licht an', language: ''), isNull);
    });

    test(
      'Teile eines Aktionssatzes zählen nicht allein („nicht weiter“)',
      () async {
        // „nicht weiter“ is „stop“; „nicht“ alone must not be known.
        expect(await args('Küche Licht nicht an'), isNull);
      },
    );

    test(
      'Rollo ohne Option „ohne Rückfrage“ oder mit anderer Klasse',
      () async {
        // The stored flag/class are not enough alone.
        expect(await args('Rollo Büro hoch'), isNull);
        expect(await args('Terrasse Markise hoch'), isNull);
        expect(await args('Garagentor zu'), isNull);
      },
    );

    test('ohne freigegebene Geräte', () async {
      final empty = HaFastPath(HaContext(FakeHaApi(), FakeHaEntityStore()));
      expect(await empty.match('Küche Licht an', language: 'de'), isNull);
    });

    test('Fehler beim Lesen des Speichers → null statt Ausnahme', () async {
      final broken = HaFastPath(HaContext(FakeHaApi(), _BrokenStore()));
      expect(await broken.match('Küche Licht an', language: 'de'), isNull);
    });
  });
}

final class _BrokenStore implements HaEntityStore {
  @override
  Future<List<HaEntity>> load() async => throw StateError('kaputt');

  @override
  Future<void> save(List<HaEntity> entities) async {}

  @override
  Future<DateTime?> lastSync() async => null;

  @override
  Future<void> saveLastSync(DateTime time) async {}
}
