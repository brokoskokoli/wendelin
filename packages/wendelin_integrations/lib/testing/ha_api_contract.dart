import 'dart:async';

import 'package:test/test.dart';

import '../src/common/port_exception.dart';
import '../src/home_assistant/ha_ports.dart';

/// Creates a [HaApi] in the contract state (the standard house of
/// `FakeHaApi.reset`) per test.
typedef HaApiFactory = FutureOr<HaApi> Function();

/// Contract every [HaApi] must pass (fake and HTTP client against a
/// rebuilt Home Assistant).
void haApiContract(HaApiFactory create, {required String name}) {
  group('HaApi-Vertrag: $name', () {
    late HaApi api;
    setUp(() async => api = await create());

    test('check meldet die Version oder leer', () async {
      expect(await api.check(), isA<String>());
    });

    test('states und state', () async {
      final all = await api.states();
      expect(
        all.map((s) => s.entityId),
        containsAll(['light.kitchen', 'lock.front']),
      );
      final s = await api.state('light.kitchen');
      expect(s.state, 'on');
      expect(s.attributes['brightness'], 200);
      expect(s.friendlyName, 'Küche Deckenlicht');
    });

    test('unbekannte Entität: notFound', () async {
      await expectLater(
        api.state('light.gibt_es_nicht'),
        throwsA(
          isA<PortException>().having(
            (e) => e.kind,
            'kind',
            PortErrorKind.notFound,
          ),
        ),
      );
    });

    test('callService ändert den Zustand', () async {
      await api.callService((
        domain: 'light',
        service: 'turn_off',
        data: {'entity_id': 'light.kitchen'},
      ));
      expect((await api.state('light.kitchen')).state, 'off');
      await api.callService((
        domain: 'light',
        service: 'turn_on',
        data: {'entity_id': 'light.kitchen', 'brightness_pct': 50},
      ));
      final s = await api.state('light.kitchen');
      expect(s.state, 'on');
      expect(s.attributes['brightness'], 128);
    });

    test('callService auf unbekannte Entität: notFound', () async {
      await expectLater(
        api.callService((
          domain: 'light',
          service: 'turn_on',
          data: {'entity_id': 'light.nope'},
        )),
        throwsA(
          isA<PortException>().having(
            (e) => e.kind,
            'kind',
            PortErrorKind.notFound,
          ),
        ),
      );
    });

    test('entities: Namen und Räume', () async {
      final list = await api.entities();
      final kitchen = list.singleWhere((e) => e.entityId == 'light.kitchen');
      expect(kitchen.name, 'Küche Deckenlicht');
      expect(kitchen.area, 'Küche');
      expect(
        list.singleWhere((e) => e.entityId == 'sensor.temp_out').area,
        isNull,
      );
    });
  });
}
