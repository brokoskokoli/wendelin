import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

const _approved = [
  HaEntity(entityId: 'light.kitchen', name: 'Küche Deckenlicht', area: 'Küche'),
  HaEntity(
    entityId: 'light.bedroom',
    name: 'Schlafzimmer Licht',
    area: 'Schlafzimmer',
  ),
  HaEntity(
    entityId: 'light.living',
    name: 'Wohnzimmer Licht',
    area: 'Wohnzimmer',
  ),
  HaEntity(entityId: 'switch.coffee', name: 'Kaffeemaschine', area: 'Küche'),
  HaEntity(entityId: 'scene.movie', name: 'Filmabend', area: 'Wohnzimmer'),
  HaEntity(entityId: 'media_player.tv', name: 'Fernseher', area: 'Wohnzimmer'),
  HaEntity(
    entityId: 'climate.living',
    name: 'Heizung Wohnzimmer',
    area: 'Wohnzimmer',
  ),
  HaEntity(entityId: 'lock.front', name: 'Haustür', area: 'Flur'),
  HaEntity(entityId: 'cover.garage', name: 'Garagentor', area: 'Garage'),
  HaEntity(
    entityId: 'alarm_control_panel.home',
    name: 'Alarmanlage',
    area: 'Flur',
  ),
  HaEntity(entityId: 'sensor.temp_out', name: 'Außentemperatur'),
];

void main() {
  late FakeHaApi api;
  late FakeHaEntityStore store;
  late HaIntegration ha;
  late List<String> errors;
  late List<PortErrorKind> kinds;
  late int recovered;

  Tool tool(String name) => ha.tools.singleWhere((t) => t.name == name);
  Future<ToolOutcome> run(String name, Map<String, Object?> args) =>
      tool(name).execute(args, ctx());
  Future<ToolOutcome> call(Map<String, Object?> args) => run('ha__call', args);
  Map<String, Object?> body(ToolOutcome o) =>
      jsonDecode(o.text.substring(haDataNotice.length + 1))
          as Map<String, Object?>;

  setUp(() {
    api = FakeHaApi();
    store = FakeHaEntityStore(_approved);
    errors = [];
    kinds = [];
    recovered = 0;
    ha = HaIntegration(
      api,
      FakeHaSecrets(const HaEndpoint(url: 'http://10.0.0.2:8123', token: 't')),
      store,
      onError: (m, k) {
        errors.add(m);
        kinds.add(k);
      },
      onRecovered: () => recovered++,
    );
  });

  group('Risiko je Domain', () {
    test('Tools und ihre Stufen', () {
      expect(
        {for (final t in ha.tools) t.name: t.risk},
        {
          'ha__list_entities': RiskLevel.read,
          'ha__state': RiskLevel.read,
          'ha__call': RiskLevel.write,
          'ha__call_secure': RiskLevel.external,
        },
      );
      for (final t in ha.tools) {
        expect(Tool.isValidToolName(t.name), isTrue);
      }
    });

    test('haRiskForDomain', () {
      for (final d in ['light', 'switch', 'scene', 'media_player', 'climate']) {
        expect(haRiskForDomain(d), RiskLevel.write, reason: d);
      }
      for (final d in ['lock', 'alarm_control_panel', 'cover']) {
        expect(haRiskForDomain(d), RiskLevel.external, reason: d);
      }
      for (final d in ['sensor', 'binary_sensor', 'script', 'automation']) {
        expect(haRiskForDomain(d), isNull, reason: d);
      }
    });

    for (final (entity, id, service) in [
      ('Haustür', 'lock.front', 'unlock'),
      ('Garagentor', 'cover.garage', 'open_cover'),
      ('Alarmanlage', 'alarm_control_panel.home', 'alarm_disarm'),
    ]) {
      test('$entity ist über ha__call nicht steuerbar', () async {
        final before = api.at(id)!.state;
        final o = await call({'entity': entity, 'service': service});
        expect(o.isError, isTrue);
        expect(o.text, contains('ha__call_secure'));
        expect(api.calls, isEmpty);
        expect(api.at(id)!.state, before);
      });
    }

    test('Licht über ha__call_secure läuft (nur strenger, WP154)', () async {
      final o = await run('ha__call_secure', {
        'entity': 'Küche Deckenlicht',
        'service': 'turn_off',
      });
      expect(o.isError, isFalse, reason: o.text);
      expect(api.calls.single.service, 'turn_off');
    });

    test('Sensor ist nur lesbar', () async {
      final o = await call({
        'entity': 'Außentemperatur',
        'service': 'turn_off',
      });
      expect(o.isError, isTrue);
      expect(o.text, contains('gelesen'));
    });

    test('secure: Bestätigungstext, kein Undo, Wirkung', () async {
      final text = await tool('ha__call_secure')
          .confirmationText({'entity': 'Haustür', 'service': 'unlock'}, ctx());
      expect(text, 'Haustür (Flur): aufschließen');
      final o = await run('ha__call_secure', {
        'entity': 'Haustür',
        'service': 'unlock',
      });
      expect(o.isError, isFalse);
      expect(o.undo, isNull);
      expect(api.at('lock.front')!.state, 'unlocked');
      await run('ha__call_secure', {
        'entity': 'Garagentor',
        'service': 'open_cover',
      });
      expect(api.at('cover.garage')!.state, 'open');
      await run('ha__call_secure', {
        'entity': 'Alarmanlage',
        'service': 'alarm_arm_away',
      });
      expect(api.at('alarm_control_panel.home')!.state, 'armed_away');
    });

    test('Dienste außerhalb der Liste werden abgelehnt', () async {
      final o = await call({
        'entity': 'Küche Deckenlicht',
        'service': 'reload',
      });
      expect(o.isError, isTrue);
      expect(api.calls, isEmpty);
    });
  });

  group('Freigegebene Entitäten', () {
    test(
      'list_entities zeigt nur freigegebene, mit Raum und Hinweis',
      () async {
        final o = await run('ha__list_entities', {});
        expect(o.text, startsWith(haDataNotice));
        expect(o.text, isNot(contains('light.secret')));
        expect(o.text, isNot(contains('Geheimes Licht')));
        final devices = (body(o)['devices']! as List)
            .cast<Map<String, Object?>>();
        expect(devices.length, _approved.length);
        expect(devices.first, {
          'id': 'light.kitchen',
          'name': 'Küche Deckenlicht',
          'area': 'Küche',
          'domain': 'light',
        });
        expect(devices.last['read_only'], isTrue);
      },
    );

    test('Filter nach Raum und Typ', () async {
      final o = await run('ha__list_entities', {
        'area': 'Wohnzimmer',
        'domain': 'light',
      });
      expect(o.text, contains('Wohnzimmer Licht'));
      expect(o.text, isNot(contains('Küche Deckenlicht')));
      expect(o.text, isNot(contains('Fernseher')));
    });

    test('nicht freigegebenes Gerät ist weder les- noch steuerbar', () async {
      for (final name in ['ha__state', 'ha__call']) {
        final o = await run(name, {
          'entity': 'light.secret',
          'service': 'turn_off',
        });
        expect(o.isError, isTrue, reason: name);
      }
      final o = await call({'entity': 'Geheimes Licht', 'service': 'turn_off'});
      expect(o.isError, isTrue);
      expect(api.calls, isEmpty);
      expect(api.at('light.secret')!.state, 'on');
    });

    test('Name oder Id, Raum zählt mit; mehrdeutig fragt nach', () async {
      for (final q in [
        'Küche Deckenlicht',
        'light.kitchen',
        'Kaffeemaschine Küche',
      ]) {
        expect(
          (await run('ha__state', {'entity': q})).isError,
          isFalse,
          reason: q,
        );
      }
      final o = await run('ha__state', {'entity': 'Licht'});
      expect(o.isError, isTrue);
      expect(o.text, contains('Mehrdeutig'));
    });

    test('nichts freigegeben: klare Meldung', () async {
      store.entities = [];
      final o = await call({'entity': 'Licht', 'service': 'turn_on'});
      expect(o.isError, isTrue);
      expect(o.text, contains('freigegeben'));
    });
  });

  group('ha__state', () {
    test('ein Gerät: Zustand, Helligkeit in Prozent, Datenhinweis', () async {
      final o = await run('ha__state', {'entity': 'Küche Deckenlicht'});
      expect(o.text, startsWith(haDataNotice));
      expect(body(o)['state'], 'on');
      expect(body(o)['brightness_pct'], 78);
      expect(body(o).containsKey('friendly_name'), isFalse);
    });

    test('ohne entity: freigegebene, gefiltert', () async {
      final o = await run('ha__state', {'domain': 'light'});
      expect(o.text, contains('Küche Deckenlicht'));
      expect(o.text, isNot(contains('Geheimes Licht')));
      expect(o.text, isNot(contains('Haustür')));
    });

    test('Texte aus HA werden gekürzt', () async {
      api.set('media_player.tv', 'playing', {'media_title': 'x' * 500});
      final o = await run('ha__state', {'entity': 'Fernseher'});
      expect(o.text.length, lessThan(600));
    });
  });

  group('ha__call mit Undo', () {
    test('Licht: Helligkeit, Undo stellt den vorherigen Zustand her', () async {
      final o = await call({
        'entity': 'Küche Deckenlicht',
        'service': 'turn_on',
        'brightness_pct': 20,
      });
      expect(o.isError, isFalse);
      expect(api.at('light.kitchen')!.attributes['brightness'], 51);
      expect(o.undo!.label, contains('Küche Deckenlicht'));
      await o.undo!();
      final s = api.at('light.kitchen')!;
      expect(s.state, 'on');
      expect(s.attributes['brightness'], 200);
    });

    test('Licht mit Farbtemperatur: Undo stellt Kelvin wieder her', () async {
      api.set('light.kitchen', 'on', {
        'color_mode': 'color_temp',
        'color_temp_kelvin': 2700,
        'rgb_color': [255, 169, 87],
      });
      final o = await call({
        'entity': 'Küche Deckenlicht',
        'service': 'turn_on',
        'rgb_color': [0, 0, 255],
      });
      expect(api.at('light.kitchen')!.attributes['rgb_color'], [0, 0, 255]);
      await o.undo!();
      final restore = api.calls.last;
      expect(restore.data['color_temp_kelvin'], 2700);
      expect(restore.data.containsKey('rgb_color'), isFalse);
      expect(api.at('light.kitchen')!.attributes['color_temp_kelvin'], 2700);
      expect(api.at('light.kitchen')!.attributes['color_mode'], 'color_temp');
    });

    test('Licht aus: Undo schaltet wieder ein', () async {
      final o = await call({
        'entity': 'Küche Deckenlicht',
        'service': 'turn_off',
      });
      expect(api.at('light.kitchen')!.state, 'off');
      await o.undo!();
      expect(api.at('light.kitchen')!.state, 'on');
    });

    test('Licht war aus: Undo schaltet wieder aus', () async {
      final o = await call({
        'entity': 'Schlafzimmer Licht',
        'service': 'turn_on',
      });
      expect(api.at('light.bedroom')!.state, 'on');
      await o.undo!();
      expect(api.at('light.bedroom')!.state, 'off');
    });

    test('Schalter', () async {
      final o = await call({'entity': 'Kaffeemaschine', 'service': 'toggle'});
      expect(api.at('switch.coffee')!.state, 'on');
      await o.undo!();
      expect(api.at('switch.coffee')!.state, 'off');
    });

    test('Szene: Snapshot, Undo stellt her und räumt auf', () async {
      final o = await call({'entity': 'Filmabend', 'service': 'turn_on'});
      expect(api.at('light.living')!.attributes['brightness'], 20);
      expect(api.calls.first.service, 'create');
      await o.undo!();
      expect(api.at('light.living')!.attributes['brightness'], 255);
      expect(api.at('media_player.tv')!.attributes['volume_level'], 0.3);
      final left = (await api.states()).where(
        (x) => x.entityId.contains('wendelin_undo'),
      );
      expect(left, isEmpty);
    });

    test('Szene: scheitert der Snapshot, läuft sie ohne Undo', () async {
      api.failNext('callService');
      final o = await call({'entity': 'Filmabend', 'service': 'turn_on'});
      expect(o.isError, isFalse);
      expect(o.undo, isNull);
      expect(api.at('light.living')!.attributes['brightness'], 20);
    });

    test('Medien: Pause, Lautstärke, Ausschalten', () async {
      var o = await call({'entity': 'Fernseher', 'service': 'media_pause'});
      expect(api.at('media_player.tv')!.state, 'paused');
      await o.undo!();
      expect(api.at('media_player.tv')!.state, 'playing');
      o = await call({
        'entity': 'Fernseher',
        'service': 'volume_set',
        'volume_pct': 80,
      });
      expect(api.at('media_player.tv')!.attributes['volume_level'], 0.8);
      await o.undo!();
      expect(api.at('media_player.tv')!.attributes['volume_level'], 0.3);
      o = await call({'entity': 'Fernseher', 'service': 'turn_off'});
      expect(api.at('media_player.tv')!.state, 'off');
      await o.undo!();
      expect(api.at('media_player.tv')!.state, isNot('off'));
      o = await call({'entity': 'Fernseher', 'service': 'media_next_track'});
      expect(o.undo, isNull);
    });

    test('Klima: Temperatur und Modus', () async {
      var o = await call({
        'entity': 'Heizung Wohnzimmer',
        'service': 'set_temperature',
        'temperature': '24,5',
      });
      expect(api.at('climate.living')!.attributes['temperature'], 24.5);
      await o.undo!();
      expect(api.at('climate.living')!.attributes['temperature'], 21);
      o = await call({
        'entity': 'Heizung Wohnzimmer',
        'service': 'set_hvac_mode',
        'hvac_mode': 'off',
      });
      expect(api.at('climate.living')!.state, 'off');
      await o.undo!();
      expect(api.at('climate.living')!.state, 'heat');
    });

    test('nicht erreichbares Gerät wird nicht angefasst', () async {
      api.set('light.kitchen', 'unavailable');
      final o = await call({
        'entity': 'Küche Deckenlicht',
        'service': 'turn_on',
      });
      expect(o.isError, isTrue);
      expect(api.calls, isEmpty);
    });

    test('Daten werden geprüft', () async {
      for (final data in <Map<String, Object?>>[
        {'brightness_pct': 101},
        {'brightness_pct': 'hell'},
        {'hvac_mode': 'heat'},
        {'volume_pct': 50},
        {
          'rgb_color': [1, 2],
        },
      ]) {
        final o = await call({
          'entity': 'Küche Deckenlicht',
          'service': 'turn_on',
          ...data,
        });
        expect(o.isError, isTrue, reason: '$data');
      }
      expect(api.calls, isEmpty);
    });
  });

  group('Fehler und Zustand', () {
    test(
      'abgelehntes Token pausiert, der nächste Erfolg hebt es auf',
      () async {
        api.failNext(
          'state',
          const PortException(PortErrorKind.permissionDenied, 'Token weg'),
        );
        final o = await run('ha__state', {'entity': 'Küche Deckenlicht'});
        expect(o.isError, isTrue);
        expect(errors, ['Token weg']);
        expect(kinds, [PortErrorKind.permissionDenied]);
        expect(
          (await run('ha__state', {'entity': 'Küche Deckenlicht'})).isError,
          isFalse,
        );
        expect(recovered, 1);
      },
    );

    test('vorübergehender Fehler pausiert nicht', () async {
      api.failNext(
        'state',
        const PortException(PortErrorKind.unavailable, 'offline'),
      );
      final o = await run('ha__state', {'entity': 'Küche Deckenlicht'});
      expect(o.text, 'offline');
      expect(errors, isEmpty);
    });

    test('reconnect', () async {
      expect(await ha.reconnect(), isNull);
      api.failNext(
        'check',
        const PortException(PortErrorKind.unavailable, 'offline'),
      );
      final f = await ha.reconnect();
      expect(f!.service, 'ha');
      expect(f.kind, PortErrorKind.unavailable);
      expect(f.message, 'offline');
    });

    test('Einrichtung: Verbindung und Geräte', () async {
      expect((await ha.setupState()).missingSteps, isEmpty);
      store.entities = [];
      expect((await ha.setupState()).missingSteps, [
        HaIntegration.entitiesStep,
      ]);
      final fresh = HaIntegration(api, FakeHaSecrets(), FakeHaEntityStore());
      expect((await fresh.setupState()).missingSteps, [
        HaIntegration.connectStep,
        HaIntegration.entitiesStep,
      ]);
    });
  });

  group('Szene mit Schloss, Alarm oder Rollo (K57)', () {
    const gehen = HaEntity(entityId: 'scene.leaving', name: 'Gehen');
    setUp(() {
      store.entities = [...store.entities, gehen];
      api.set('scene.leaving', 'scening', {
        'friendly_name': 'Gehen',
        'entity_id': ['light.living', 'lock.front'],
      });
    });

    test('ha__call lehnt die Szene ab, nichts wird aufgerufen', () async {
      final o = await call({'entity': 'Gehen', 'service': 'turn_on'});
      expect(o.isError, isTrue);
      expect(o.text, contains('ha__call_secure'));
      expect(api.calls, isEmpty);
    });

    test('ha__call_secure fragt nach und führt sie ohne Undo aus', () async {
      final t = tool('ha__call_secure');
      expect(t.risk, RiskLevel.external);
      expect(
        await t.confirmationText({
          'entity': 'Gehen',
          'service': 'turn_on',
        }, ctx()),
        'Gehen: einschalten',
      );
      final o = await run('ha__call_secure', {
        'entity': 'Gehen',
        'service': 'turn_on',
      });
      expect(o.isError, isFalse);
      expect(o.undo, isNull);
      expect(api.calls.single.domain, 'scene');
    });

    test(
      'Szene ohne kritische Mitglieder: ha__call offen, secure auch',
      () async {
        final o = await run('ha__call_secure', {
          'entity': 'Filmabend',
          'service': 'turn_on',
        });
        expect(o.isError, isFalse, reason: o.text);
        expect(api.calls.single.domain, 'scene');
        expect(
          (await call({'entity': 'Filmabend', 'service': 'turn_on'})).isError,
          isFalse,
        );
      },
    );

    test('Szene mit Rollo oder Alarm zählt ebenso', () async {
      for (final member in ['cover.garage', 'alarm_control_panel.home']) {
        api.set('scene.leaving', 'scening', {
          'entity_id': ['light.living', member],
        });
        final o = await call({'entity': 'Gehen', 'service': 'turn_on'});
        expect(o.isError, isTrue, reason: member);
      }
      expect(api.calls, isEmpty);
    });

    test('entity_id keine Liste: kritisch (fail closed)', () async {
      api.set('scene.leaving', 'scening', {'entity_id': 'lock.front'});
      final o = await call({'entity': 'Gehen', 'service': 'turn_on'});
      expect(o.isError, isTrue);
      expect(o.text, contains('ha__call_secure'));
      expect(api.calls, isEmpty);
      expect(
        (await run('ha__call_secure', {
          'entity': 'Gehen',
          'service': 'turn_on',
        })).isError,
        isFalse,
      );
      expect(await _locked(ha, 'Gehen'), isFalse);
    });

    test('ohne entity_id (Hue): offen, aber gesperrt nicht erlaubt', () async {
      store.entities = [
        ...store.entities,
        const HaEntity(entityId: 'scene.hue', name: 'Hue Abend'),
      ];
      api.set('scene.hue', 'scening', {'friendly_name': 'Hue Abend'});
      final o = await call({'entity': 'Hue Abend', 'service': 'turn_on'});
      expect(o.isError, isFalse);
      expect(await _locked(ha, 'Hue Abend'), isFalse);
      expect(await _locked(ha, 'Filmabend'), isTrue);
    });

    test('Mitglied group.* oder Schalter mit Bestätigung: kritisch', () async {
      store.entities = [
        for (final e in store.entities)
          e.entityId == 'switch.coffee' ? e.withConfirm(true) : e,
      ];
      for (final member in ['group.alle_lichter', 'switch.coffee']) {
        api.set('scene.leaving', 'scening', {
          'entity_id': ['light.living', member],
        });
        final o = await call({'entity': 'Gehen', 'service': 'turn_on'});
        expect(o.isError, isTrue, reason: member);
        expect(await _locked(ha, 'Gehen'), isFalse, reason: member);
      }
      expect(api.calls, isEmpty);
    });

    test('nicht erlaubt, solange gesperrt', () async {
      expect(
        await ha.allowedWhileLocked('ha__call', {
          'entity': 'Gehen',
          'service': 'turn_on',
        }),
        isFalse,
      );
      expect(
        await ha.allowedWhileLocked('ha__call', {
          'entity': 'Filmabend',
          'service': 'turn_on',
        }),
        isTrue,
      );
    });
  });

  group('Schalter „immer bestätigen“ (K57)', () {
    setUp(() {
      store.entities = [
        for (final e in store.entities)
          e.entityId == 'switch.coffee' ? e.withConfirm(true) : e,
      ];
    });

    test('ha__call lehnt ab, ha__call_secure fragt und führt aus', () async {
      final o = await call({'entity': 'Kaffeemaschine', 'service': 'turn_on'});
      expect(o.isError, isTrue);
      expect(o.text, contains('ha__call_secure'));
      expect(api.calls, isEmpty);
      final t = tool('ha__call_secure');
      expect(
        await t.confirmationText({
          'entity': 'Kaffeemaschine',
          'service': 'turn_on',
        }, ctx()),
        'Kaffeemaschine (Küche): einschalten',
      );
      final r = await run('ha__call_secure', {
        'entity': 'Kaffeemaschine',
        'service': 'turn_on',
      });
      expect(r.isError, isFalse);
      expect(api.at('switch.coffee')!.state, 'on');
    });

    test(
      'ohne die Option nimmt ha__call_secure den Schalter trotzdem',
      () async {
        store.entities = [for (final e in store.entities) e.withConfirm(false)];
        final o = await run('ha__call_secure', {
          'entity': 'Kaffeemaschine',
          'service': 'turn_on',
        });
        expect(o.isError, isFalse, reason: o.text);
        expect(api.calls.single.service, 'turn_on');
      },
    );

    test('Licht mit „Immer bestätigen“: gesperrt nicht erlaubt', () async {
      store.entities = [
        for (final e in store.entities)
          e.entityId.startsWith('light.') ? e.withConfirm(true) : e,
      ];
      expect(await _locked(ha, 'Küche Deckenlicht'), isFalse);
    });

    test('Haken für WP92: nicht erlaubt, solange gesperrt', () async {
      expect(
        await ha.allowedWhileLocked('ha__call', {'entity': 'Kaffeemaschine'}),
        isFalse,
      );
    });

    test('Option überlebt JSON', () {
      const e = HaEntity(entityId: 'switch.a', name: 'A', alwaysConfirm: true);
      expect(HaEntity.fromJson(e.toJson()), e);
      expect(
        HaEntity.fromJson(
          const HaEntity(entityId: 'switch.a', name: 'A').toJson(),
        )!.alwaysConfirm,
        isFalse,
      );
    });
  });

  test('Integration ist sensibel (Schloss-, Alarm-, Anwesenheitsdaten)', () {
    expect(ha.sensitive, isTrue);
  });

  group('Haken für WP92 (gesperrt erlaubt)', () {
    Future<bool> allowed(String tool, String entity) =>
        ha.allowedWhileLocked(tool, {'entity': entity, 'service': 'turn_on'});

    test('Licht, Szene, Medien ja', () async {
      expect(await allowed('ha__call', 'Küche Deckenlicht'), isTrue);
      expect(await allowed('ha__call', 'Filmabend'), isTrue);
      expect(await allowed('ha__call', 'Fernseher'), isTrue);
    });

    test('alles andere nein', () async {
      for (final e in [
        'Haustür',
        'Garagentor',
        'Alarmanlage',
        'Heizung Wohnzimmer',
        'Kaffeemaschine',
        'Geheimes Licht',
      ]) {
        expect(await allowed('ha__call', e), isFalse, reason: e);
      }
      expect(await allowed('ha__call_secure', 'Haustür'), isFalse);
      expect(await allowed('ha__state', 'Küche Deckenlicht'), isFalse);
      expect(await allowed('ha__list_entities', 'x'), isFalse);
    });
  });

  group('feste Bestätigung', () {
    test('Licht an und aus ohne Daten', () async {
      final t = tool('ha__call');
      expectFixed(
        await call({'entity': 'Küche Deckenlicht', 'service': 'turn_off'}),
        t,
        'ha.off',
        de: 'Ich habe Küche Deckenlicht ausgeschaltet.',
      );
      expectFixed(
        await call({'entity': 'Küche Deckenlicht', 'service': 'turn_on'}),
        t,
        'ha.on',
        de: 'Ich habe Küche Deckenlicht eingeschaltet.',
      );
    });

    test('mit mehreren Werten (Helligkeit und Farbe) → Modell', () async {
      final o = await call({
        'entity': 'Küche Deckenlicht',
        'service': 'turn_on',
        'brightness_pct': 20,
        'rgb_color': [255, 0, 0],
      });
      expect(o.isError, isFalse);
      expect(o.fixed, isNull);
    });

    test('Szene → Modell formuliert', () async {
      api.set('scene.movie', 'scening', {
        'entity_id': ['light.living'],
      });
      final o = await call({'entity': 'Filmabend', 'service': 'turn_on'});
      expect(o.isError, isFalse);
      expect(o.fixed, isNull);
    });

    test('anderer Dienst (Heizmodus) → Modell formuliert', () async {
      final o = await call({
        'entity': 'Heizung Wohnzimmer',
        'service': 'set_hvac_mode',
        'hvac_mode': 'off',
      });
      expect(o.isError, isFalse);
      expect(o.fixed, isNull);
    });

    test('nicht erlaubter Dienst → Fehler ohne Satz', () async {
      final o = await call({'entity': 'Haustür', 'service': 'unlock'});
      expect(o.isError, isTrue);
      expect(o.fixed, isNull);
    });
  });
}

Future<bool> _locked(HaIntegration ha, String entity) =>
    ha.allowedWhileLocked('ha__call', {'entity': entity, 'service': 'turn_on'});
