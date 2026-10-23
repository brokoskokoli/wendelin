import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

/// Fixed confirmations for covers, position, brightness and temperature
/// (WP135 C): the sentence carries the values of the call that Home Assistant
/// accepted; errors and everything else leave the answer to the model.
const _devices = [
  HaEntity(
    entityId: 'light.living',
    name: 'Licht Wohnzimmer',
    area: 'Wohnzimmer',
  ),
  HaEntity(
    entityId: 'cover.blind',
    name: 'Rollo Wohnzimmer',
    area: 'Wohnzimmer',
  ),
  HaEntity(entityId: 'cover.garage', name: 'Garagentor', area: 'Garage'),
  HaEntity(
    entityId: 'climate.living',
    name: 'Heizung Wohnzimmer',
    area: 'Wohnzimmer',
  ),
  HaEntity(entityId: 'lock.front', name: 'Haustür', area: 'Flur'),
];

void main() {
  late FakeHaApi api;
  late HaIntegration ha;

  Tool tool(String name) => ha.tools.singleWhere((t) => t.name == name);
  Future<ToolOutcome> secure(Map<String, Object?> args) =>
      tool('ha__call_secure').execute(args, ctx());
  Future<ToolOutcome> call(Map<String, Object?> args) =>
      tool('ha__call').execute(args, ctx());
  String text(ToolOutcome o, String lang) =>
      renderConfirmation(o.fixed!, lang)!;

  setUp(() {
    api = FakeHaApi()
      ..set('cover.blind', 'open', {
        'friendly_name': 'Rollo Wohnzimmer',
        'device_class': 'blind',
        'current_position': 100,
      });
    ha = HaIntegration(
      api,
      FakeHaSecrets(const HaEndpoint(url: 'http://10.0.0.2:8123', token: 't')),
      FakeHaEntityStore(_devices),
    );
  });

  group('Rollo', () {
    test(
      'öffnen, schließen, stoppen: ein Satz je Aktion, drei Sprachen',
      () async {
        final t = tool('ha__call_secure');
        final cases = {
          'open_cover': (
            'ha.cover.open',
            'Ich habe Rollo Wohnzimmer geöffnet.',
            'I opened Rollo Wohnzimmer.',
            'J’ai ouvert Rollo Wohnzimmer.',
          ),
          'close_cover': (
            'ha.cover.close',
            'Ich habe Rollo Wohnzimmer geschlossen.',
            'I closed Rollo Wohnzimmer.',
            'J’ai fermé Rollo Wohnzimmer.',
          ),
          'stop_cover': (
            'ha.cover.stop',
            'Ich habe Rollo Wohnzimmer angehalten.',
            'I stopped Rollo Wohnzimmer.',
            'J’ai arrêté Rollo Wohnzimmer.',
          ),
        };
        for (final MapEntry(:key, :value) in cases.entries) {
          final o = await secure({
            'entity': 'Rollo Wohnzimmer',
            'service': key,
          });
          expectFixed(o, t, value.$1, de: value.$2);
          expect(text(o, 'en'), value.$3);
          expect(text(o, 'fr'), value.$4);
        }
      },
    );

    test('Position mit Wert aus dem Aufruf, auch „Lampe“-Auflösung', () async {
      final o = await secure({
        'entity': 'Rollo Wohnzimmer',
        'service': 'set_cover_position',
        'position_pct': 50,
      });
      expectFixed(
        o,
        tool('ha__call_secure'),
        'ha.cover.position',
        de: 'Ich habe Rollo Wohnzimmer auf 50 Prozent gestellt.',
      );
      expect(text(o, 'en'), 'I set Rollo Wohnzimmer to 50 percent.');
      expect(text(o, 'fr'), 'J’ai réglé Rollo Wohnzimmer à 50 pour cent.');
      expect(api.at('cover.blind')!.attributes['current_position'], 50);
      expect(api.calls.single.service, 'set_cover_position');
      expect(api.calls.single.data['position'], 50);
    });

    test('Position braucht eine Zahl von 0 bis 100', () async {
      for (final v in [101, -1, 'halb', null]) {
        final o = await secure({
          'entity': 'Rollo Wohnzimmer',
          'service': 'set_cover_position',
          'position_pct': ?v,
        });
        expect(o.isError, isTrue, reason: '$v');
        expect(o.fixed, isNull);
      }
      expect(api.calls, isEmpty);
    });

    test('Wert passt nicht zum Dienst: Fehler ohne Satz', () async {
      final o = await secure({
        'entity': 'Rollo Wohnzimmer',
        'service': 'open_cover',
        'position_pct': 50,
      });
      expect(o.isError, isTrue);
      expect(o.fixed, isNull);
      expect(api.calls, isEmpty);
    });

    test('Fehler von Home Assistant: kein Satz', () async {
      api.failNext(
        'callService',
        const PortException(PortErrorKind.unavailable, 'offline'),
      );
      final o = await secure({
        'entity': 'Rollo Wohnzimmer',
        'service': 'close_cover',
      });
      expect(o.isError, isTrue);
      expect(o.fixed, isNull);
    });

    test('nicht erreichbares Gerät: Fehler ohne Satz', () async {
      api.set('cover.blind', 'unavailable');
      final o = await secure({
        'entity': 'Rollo Wohnzimmer',
        'service': 'close_cover',
      });
      expect(o.isError, isTrue);
      expect(o.fixed, isNull);
    });

    test(
      'Rollo bleibt bei ha__call gesperrt (Bestätigung bleibt Pflicht)',
      () async {
        final o = await call({
          'entity': 'Rollo Wohnzimmer',
          'service': 'close_cover',
        });
        expect(o.isError, isTrue);
        expect(o.fixed, isNull);
        expect(api.calls, isEmpty);
      },
    );

    test('Schloss: kein Satz, auch nicht über Cover-Schlüssel', () async {
      final o = await secure({'entity': 'Haustür', 'service': 'unlock'});
      expect(o.isError, isFalse);
      expect(o.fixed, isNull);
    });

    test('Cover-Schlüssel: ha__call nur für ruhige Rollos (WP135 E)', () async {
      const keys = {
        'ha.cover.open',
        'ha.cover.close',
        'ha.cover.stop',
        'ha.cover.position',
      };
      expect(
        (tool('ha__call_secure') as FixedConfirmationTool).confirmationKeys,
        keys,
      );
      expect(
        (tool('ha__call') as FixedConfirmationTool).confirmationKeys,
        containsAll(keys),
      );
      // Without the option the blind is refused at ha__call.
      final o = await call({'entity': 'Rollo', 'service': 'close_cover'});
      expect(o.isError, isTrue);
      expect(api.calls, isEmpty);
    });
  });

  group('Licht und Heizung', () {
    test('Helligkeit allein: Satz mit dem Wert', () async {
      final o = await call({
        'entity': 'Licht Wohnzimmer',
        'service': 'turn_on',
        'brightness_pct': 30,
      });
      expectFixed(
        o,
        tool('ha__call'),
        'ha.brightness',
        de: 'Ich habe Licht Wohnzimmer auf 30 Prozent Helligkeit gestellt.',
      );
      expect(text(o, 'en'), 'I set Licht Wohnzimmer to 30 percent brightness.');
      expect(
        text(o, 'fr'),
        'J’ai réglé Licht Wohnzimmer à 30 pour cent de luminosité.',
      );
    });

    test('Helligkeit mit Farbe, Aus mit Helligkeit: Modell', () async {
      final a = await call({
        'entity': 'Licht Wohnzimmer',
        'service': 'turn_on',
        'brightness_pct': 30,
        'color_temp_kelvin': 2700,
      });
      expect(a.isError, isFalse);
      expect(a.fixed, isNull);
    });

    test('Temperatur: Satz mit dem Wert, Komma nach Sprache', () async {
      final o = await call({
        'entity': 'Heizung Wohnzimmer',
        'service': 'set_temperature',
        'temperature': '21,5',
      });
      expectFixed(
        o,
        tool('ha__call'),
        'ha.temperature',
        de: 'Ich habe Heizung Wohnzimmer auf 21,5 Grad gestellt.',
      );
      expect(text(o, 'en'), 'I set Heizung Wohnzimmer to 21.5 degrees.');
      expect(text(o, 'fr'), 'J’ai réglé Heizung Wohnzimmer sur 21,5 degrés.');
      expect(api.at('climate.living')!.attributes['temperature'], 21.5);
    });

    test('ganze Temperatur ohne Nachkomma', () async {
      final o = await call({
        'entity': 'Heizung Wohnzimmer',
        'service': 'set_temperature',
        'temperature': '22.0',
      });
      expect(
        text(o, 'de'),
        'Ich habe Heizung Wohnzimmer auf 22 Grad gestellt.',
      );
    });

    test('Temperatur außerhalb: Fehler ohne Satz', () async {
      final o = await call({
        'entity': 'Heizung Wohnzimmer',
        'service': 'set_temperature',
        'temperature': '500',
      });
      expect(o.isError, isTrue);
      expect(o.fixed, isNull);
    });
  });
}
