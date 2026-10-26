import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

/// Security level per device (WP154, ADR 0022): the default table (today's
/// behavior), the chosen level, fail-closed on a manipulated level, the
/// routing to `ha__call` / `ha__call_secure`, and the migration of the old
/// flags.
HaEntity _e(
  String id, {
  String? level,
  bool confirm = false,
  bool quiet = false,
  String? cls,
}) => HaEntity(
  entityId: id,
  name: 'Gerät',
  alwaysConfirm: confirm,
  noConfirm: quiet,
  deviceClass: cls,
  level: level,
);

HaState _s(String id, [Map<String, Object?> attrs = const {}]) =>
    HaState(entityId: id, state: 'on', attributes: attrs);

void main() {
  const a = LevelAccess.allowed;
  const c = LevelAccess.confirm;
  const u = LevelAccess.unlock;

  group('Standardstufe je Gerät (heutiges Verhalten)', () {
    final cases = <(String, HaEntity, HaState?, SecurityLevel)>[
      ('Licht', _e('light.a'), null, SecurityLevel.b),
      ('Medien', _e('media_player.a'), null, SecurityLevel.b),
      ('Schalter', _e('switch.a'), null, SecurityLevel.c),
      ('Heizung', _e('climate.a'), null, SecurityLevel.c),
      ('Schloss', _e('lock.a'), null, SecurityLevel.d),
      ('Alarm', _e('alarm_control_panel.a'), null, SecurityLevel.d),
      ('Garage', _e('cover.a', cls: 'garage'), null, SecurityLevel.d),
      ('Rollo ohne Option', _e('cover.a', cls: 'blind'), null, SecurityLevel.d),
      (
        'Rollo mit Option, Klasse blind',
        _e('cover.a', quiet: true, cls: 'blind'),
        _s('cover.a', {'device_class': 'blind'}),
        SecurityLevel.c,
      ),
      (
        'Rollo mit Option, live Garage',
        _e('cover.a', quiet: true, cls: 'blind'),
        _s('cover.a', {'device_class': 'garage'}),
        SecurityLevel.d,
      ),
      (
        'Licht, immer bestätigen',
        _e('light.a', confirm: true),
        null,
        SecurityLevel.d,
      ),
      (
        'Szene, sichere Mitglieder',
        _e('scene.a'),
        _s('scene.a', {
          'entity_id': ['light.x'],
        }),
        SecurityLevel.b,
      ),
      (
        'Szene, Mitglieder unbekannt (Hue)',
        _e('scene.a'),
        _s('scene.a'),
        SecurityLevel.c,
      ),
      (
        'Szene mit Schloss',
        _e('scene.a'),
        _s('scene.a', {
          'entity_id': ['lock.x'],
        }),
        SecurityLevel.d,
      ),
      ('Szene ohne Zustand', _e('scene.a'), null, SecurityLevel.d),
      ('unbekannte Domäne', _e('vacuum.a'), null, SecurityLevel.d),
    ];
    for (final (name, e, state, level) in cases) {
      test(name, () {
        final live = state != null && state.entityId == e.entityId
            ? state
            : null;
        final eff = haEffectiveLevel(
          e,
          liveClass: live?.attributes['device_class'],
          scene: e.domain == 'scene' && live != null
              ? haSceneKindOf(live)
              : HaSceneKind.critical,
        );
        expect(eff, level);
        expect(haDecide(e, state: state), levelAccess(level));
      });
    }

    test('Szene mit Mitglied auf Stufe D ist kritisch (K57)', () {
      final s = _s('scene.a', {
        'entity_id': ['switch.pumpe'],
      });
      expect(haDecide(_e('scene.a'), state: s), a);
      expect(
        haDecide(_e('scene.a'), state: s, criticalIds: {'switch.pumpe'}),
        c,
      );
    });
  });

  group('gewählte Stufe', () {
    test('überschreibt den Standard in beide Richtungen', () {
      expect(haDecide(_e('lock.a', level: 'a')), a);
      expect(haDecide(_e('light.a', level: 'd')), c);
      expect(haDecide(_e('lock.a', level: 'c')), a);
    });
    test('gesperrt × Stimme folgt der Tabelle', () {
      for (final (l, locked, voice, want) in [
        ('a', true, false, a),
        ('b', true, false, u),
        ('b', true, true, a),
        ('c', true, true, u),
        ('d', true, true, u),
      ]) {
        expect(
          haDecide(
            _e('light.a', level: l),
            locked: locked,
            speakerRecognized: voice,
          ),
          want,
          reason: '$l $locked $voice',
        );
      }
    });
    test('manipulierte oder ungültige Stufe = D, nie der Standard', () {
      for (final raw in ['', 'x', 'A', 'z', 'null']) {
        expect(haDecide(_e('light.a', level: raw)), c, reason: raw);
        expect(
          haDecide(_e('light.a', level: raw), locked: true),
          u,
          reason: raw,
        );
      }
      final json = {'id': 'light.a', 'name': 'X', 'level': 7};
      expect(HaEntity.fromJson(json)!.level, '');
      expect(haDecide(HaEntity.fromJson(json)!), c);
      expect(HaEntity.fromJson({'id': 'light.a', 'name': 'X'})!.level, isNull);
    });
    test('Rundlauf und withLevel löscht die alten Schalter', () {
      final e = _e(
        'switch.a',
        confirm: true,
        quiet: true,
      ).withLevel(SecurityLevel.a);
      expect(e.alwaysConfirm, isFalse);
      expect(e.noConfirm, isFalse);
      expect(HaEntity.fromJson(e.toJson()), e);
      expect(e.withLevel(null).level, isNull);
      expect(haDecide(e.withLevel(null)), a);
    });
  });

  group('Werkzeugwahl', () {
    late FakeHaApi api;
    HaIntegration ha(List<HaEntity> devices) => HaIntegration(
      api,
      FakeHaSecrets(const HaEndpoint(url: 'http://10.0.0.2:8123', token: 't')),
      FakeHaEntityStore(devices),
    );
    Future<ToolOutcome> run(
      HaIntegration h,
      String tool,
      String id,
      String s,
    ) => h.tools.singleWhere((t) => t.name == tool).execute({
      'entity': id,
      'service': s,
    }, ctx());

    setUp(() => api = FakeHaApi());

    test(
      'Schloss auf A läuft über ha__call, auf D nur über ha__call_secure',
      () async {
        final open = ha([_e('lock.front', level: 'a')]);
        final r = await run(open, 'ha__call', 'lock.front', 'unlock');
        expect(r.isError, isFalse, reason: r.text);
        expect(api.calls.single.service, 'unlock');
        expect(r.undo, isNull);
        api.calls.clear();
        // Nur strenger: mit Rückfrage geht es auch über ha__call_secure.
        expect(
          (await run(open, 'ha__call_secure', 'lock.front', 'lock')).isError,
          isFalse,
        );
        api.calls.clear();
        final dflt = ha([_e('lock.front')]);
        final denied = await run(dflt, 'ha__call', 'lock.front', 'unlock');
        expect(denied.isError, isTrue);
        expect(denied.text, contains('ha__call_secure'));
        expect(api.calls, isEmpty);
      },
    );

    test('Licht auf D geht nur über ha__call_secure', () async {
      final h = ha([_e('light.kitchen', level: 'd')]);
      expect(
        (await run(h, 'ha__call', 'light.kitchen', 'turn_on')).isError,
        isTrue,
      );
      expect(api.calls, isEmpty);
      final r = await run(h, 'ha__call_secure', 'light.kitchen', 'turn_on');
      expect(r.isError, isFalse, reason: r.text);
    });

    test(
      'ruhiges Rollo geht auch über ha__call_secure, ein Licht nicht',
      () async {
        api.set('cover.living', 'open', {'device_class': 'blind'});
        final h = ha([
          _e('cover.living', quiet: true, cls: 'blind'),
          _e('light.kitchen'),
        ]);
        // ha__call nimmt das Rollo (Stufe C); ha__call_secure fragt zusätzlich.
        final viaCall = await run(h, 'ha__call', 'cover.living', 'close_cover');
        expect(viaCall.isError, isFalse, reason: viaCall.text);
        final viaSecure = await run(
          h,
          'ha__call_secure',
          'cover.living',
          'close_cover',
        );
        expect(viaSecure.isError, isFalse, reason: viaSecure.text);
        expect(api.calls, hasLength(2));
        // Auch ein Licht auf B darf mit Rückfrage laufen (nur strenger): nach
        // der bestätigten Karte kein Fehler, kein Umweg über ha__call.
        api.calls.clear();
        final light = await run(
          h,
          'ha__call_secure',
          'light.kitchen',
          'turn_on',
        );
        expect(light.isError, isFalse, reason: light.text);
        expect(api.calls.single.service, 'turn_on');
        // Ebenso ein Schloss auf A.
        api.calls.clear();
        final lock = await run(
          ha([_e('lock.front', level: 'a')]),
          'ha__call_secure',
          'lock.front',
          'lock',
        );
        expect(lock.isError, isFalse, reason: lock.text);
        expect(api.calls.single.service, 'lock');
      },
    );

    test(
      'Migration: alter Schalter „immer bestätigen“ = D, ohne Änderung',
      () async {
        final old = HaEntity.fromJson({
          'id': 'switch.coffee',
          'name': 'Kaffee',
          'confirm': true,
        })!;
        final h = ha([old]);
        expect(
          (await run(h, 'ha__call', old.entityId, 'turn_on')).isError,
          isTrue,
        );
        expect(
          (await run(h, 'ha__call_secure', old.entityId, 'turn_on')).isError,
          isFalse,
        );
      },
    );

    test('Szene mit Schloss bleibt kritisch, Standard', () async {
      api.set('scene.leaving', 'scening', {'entity_id': 'lock.front'});
      final h = ha([_e('scene.leaving')]);
      expect(
        (await run(h, 'ha__call', 'scene.leaving', 'turn_on')).isError,
        isTrue,
      );
      expect(api.calls, isEmpty);
    });

    test('Szene mit Mitglied auf gewählter Stufe D läuft nur bestätigt', () async {
      api.set('scene.movie', 'scening', {
        'entity_id': ['light.dim'],
      });
      // Ohne Wahl ist das Licht harmlos: die Szene läuft über ha__call.
      final plain = ha([_e('scene.movie'), _e('light.dim')]);
      final r = await run(plain, 'ha__call', 'scene.movie', 'turn_on');
      expect(r.isError, isFalse, reason: r.text);
      api.calls.clear();
      // Der Nutzer stellt das Licht auf D (nicht das alte „immer bestätigen“).
      final h = ha([_e('scene.movie'), _e('light.dim', level: 'd')]);
      expect(
        (await run(h, 'ha__call', 'scene.movie', 'turn_on')).isError,
        isTrue,
      );
      expect(api.calls, isEmpty);
      expect(
        (await run(h, 'ha__call_secure', 'scene.movie', 'turn_on')).isError,
        isFalse,
      );
    });

    test('allowedWhileLocked folgt der Tabelle (Hook, L1 ungenutzt)', () async {
      final h = ha([
        _e('light.kitchen'),
        _e('switch.coffee'),
        _e('lock.front'),
        _e('light.dim', level: 'd'),
        _e('lock.garden', level: 'a'),
      ]);
      Future<bool> ok(String e) =>
          h.allowedWhileLocked('ha__call', {'entity': e, 'service': 'turn_on'});
      expect(await ok('light.kitchen'), isTrue);
      expect(await ok('switch.coffee'), isFalse);
      expect(await ok('lock.front'), isFalse);
      expect(await ok('light.dim'), isFalse);
      expect(await ok('lock.garden'), isTrue);
    });
  });
}
