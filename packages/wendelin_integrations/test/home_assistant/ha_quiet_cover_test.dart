import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/src/home_assistant/ha_context.dart';
import 'package:wendelin_integrations/src/home_assistant/ha_prompt.dart';
import 'package:wendelin_integrations/src/home_assistant/ha_sync.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

/// Blinds „ohne Rückfrage“ (WP135 E): only for the classes shutter, blind,
/// awning and curtain, only with the flag, decided by the live state at every
/// call; everything else stays with the confirmation.
HaEntity _cover(
  String id, {
  bool quiet = true,
  String? stored = 'blind',
  bool confirm = false,
}) => HaEntity(
  entityId: id,
  name: 'Rollo Test',
  area: 'Wohnzimmer',
  noConfirm: quiet,
  deviceClass: stored,
  alwaysConfirm: confirm,
);

void main() {
  late FakeHaApi api;

  HaIntegration ha(List<HaEntity> devices) => HaIntegration(
    api,
    FakeHaSecrets(const HaEndpoint(url: 'http://10.0.0.2:8123', token: 't')),
    FakeHaEntityStore(devices),
  );
  Tool tool(HaIntegration h, String name) =>
      h.tools.singleWhere((t) => t.name == name);
  Future<ToolOutcome> call(HaIntegration h, Map<String, Object?> args) =>
      tool(h, 'ha__call').execute(args, ctx());

  setUp(() {
    api = FakeHaApi()
      ..set('cover.blind', 'open', {
        'friendly_name': 'Rollo Test',
        'device_class': 'blind',
        'current_position': 80,
      });
  });

  group('erlaubte Klassen', () {
    for (final cls in haQuietCoverClasses) {
      test('$cls läuft über ha__call mit Undo und festem Satz', () async {
        api.set('cover.blind', 'open', {'device_class': cls});
        final h = ha([_cover('cover.blind', stored: cls)]);
        final r = await call(h, {
          'entity': 'cover.blind',
          'service': 'close_cover',
        });
        expect(r.isError, isFalse, reason: r.text);
        expect(r.fixed?.key, 'ha.cover.close');
        expect(api.calls.single.service, 'close_cover');
        expect(r.undo, isNotNull);
        api.set('cover.blind', 'closed', {'current_position': 0});
        await r.undo!.run();
        expect(api.calls.last.service, 'set_cover_position');
        expect(api.calls.last.data['position'], 80);
      });
    }

    test('Position über ha__call', () async {
      final h = ha([_cover('cover.blind')]);
      final r = await call(h, {
        'entity': 'cover.blind',
        'service': 'set_cover_position',
        'position_pct': 50,
      });
      expect(r.isError, isFalse, reason: r.text);
      expect(r.fixed?.key, 'ha.cover.position');
      expect(api.calls.single.data['position'], 50);
    });

    test('ha__call bietet die Cover-Dienste im Schema an', () {
      final props =
          tool(ha([]), 'ha__call').inputSchema['properties']!
              as Map<String, Object?>;
      final service = props['service']! as Map<String, Object?>;
      expect(service['enum'], contains('close_cover'));
    });
  });

  group('bleibt mit Bestätigung (fail-closed)', () {
    Future<void> rejected(HaIntegration h, {String id = 'cover.blind'}) async {
      final r = await call(h, {'entity': id, 'service': 'close_cover'});
      expect(r.isError, isTrue);
      expect(r.text, contains('ha__call_secure'));
      expect(api.calls, isEmpty, reason: 'nichts geht an Home Assistant');
    }

    test('ohne Option', () async {
      await rejected(ha([_cover('cover.blind', quiet: false)]));
    });

    for (final cls in ['garage', 'gate', 'door', 'window', 'damper']) {
      test('Klasse $cls trotz Option und gespeicherter Klasse blind', () async {
        api.set('cover.blind', 'open', {'device_class': cls});
        await rejected(ha([_cover('cover.blind')]));
      });
    }

    test('Klasse fehlt im Live-Zustand', () async {
      api.set('cover.nocls', 'open', {'friendly_name': 'Rollo Test'});
      await rejected(ha([_cover('cover.nocls')]), id: 'cover.nocls');
    });

    test('Garagentor mit manipuliertem Flag und Klasse shutter', () async {
      final h = ha([_cover('cover.garage', stored: 'shutter')]);
      await rejected(h, id: 'cover.garage');
    });

    test('„Immer bestätigen“ gewinnt', () async {
      await rejected(ha([_cover('cover.blind', confirm: true)]));
    });

    test('Zustand nicht lesbar → Fehler statt Aufruf', () async {
      final h = ha([_cover('cover.blind')]);
      api.failNext(
        'state',
        const PortException(PortErrorKind.unavailable, 'x'),
      );
      final r = await call(h, {
        'entity': 'cover.blind',
        'service': 'close_cover',
      });
      expect(r.isError, isTrue);
      expect(api.calls, isEmpty);
    });

    test('Sperrbildschirm: Cover nie erlaubt', () async {
      final h = ha([_cover('cover.blind')]);
      expect(
        await h.allowedWhileLocked('ha__call', {'entity': 'cover.blind'}),
        isFalse,
      );
    });

    test('ha__call_secure fragt weiter nach (Bestätigung vorbereitet)', () {
      final t = tool(ha([_cover('cover.blind')]), 'ha__call_secure');
      expect(t.risk, RiskLevel.external);
    });
  });

  group('Entität', () {
    test('JSON-Rundlauf mit Klasse und Option', () {
      final e = _cover('cover.blind', stored: 'shutter');
      expect(HaEntity.fromJson(e.toJson()), e);
      expect(HaEntity.fromJson(e.toJson())!.noConfirm, isTrue);
    });

    test('Abgleich übernimmt die Klasse, behält die Option', () {
      final next = haReconcile(
        [_cover('cover.blind', stored: 'blind')],
        [
          const HaEntity(
            entityId: 'cover.blind',
            name: 'Rollo Test',
            deviceClass: 'garage',
          ),
        ],
      )!;
      expect(next.single.deviceClass, 'garage');
      expect(next.single.noConfirm, isTrue);
    });

    test('Liste aus Home Assistant trägt die Klasse', () async {
      final all = await api.entities();
      expect(
        all.singleWhere((e) => e.entityId == 'cover.garage').deviceClass,
        'garage',
      );
    });

    test('Prompt: Beispiel mit ha__call nur für ruhige Rollos', () async {
      final quiet = await haPromptSection(
        HaContext(api, FakeHaEntityStore([_cover('cover.blind')])),
        'Rollo runter',
      );
      expect(quiet, contains('Beispiel: ha__call {"entity":"cover.blind"'));
      final secure = await haPromptSection(
        HaContext(
          api,
          FakeHaEntityStore([_cover('cover.blind', quiet: false)]),
        ),
        'Rollo runter',
      );
      expect(secure, contains('ha__call_secure {"entity":"cover.blind"'));
    });
  });
}
