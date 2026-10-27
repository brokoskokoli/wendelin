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
  String name = 'Gerät',
  String? level,
  bool confirm = false,
  bool quiet = false,
  String? cls,
}) => HaEntity(
  entityId: id,
  name: name,
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
    test('Tabelle Stimme aus der Eingabe × Stufe × Gerät (WP154 L3)', () {
      final voices = <String, UserInput>{
        'erkannt': UserInput(
          text: 'x',
          source: InputSource.voice,
          speakerId: 'p',
        ),
        'unbekannt': UserInput(text: 'x', source: InputSource.voice),
        'getippt': UserInput(text: 'x'),
        'Fehler': UserInput(text: 'x', source: InputSource.voice),
      };
      for (final id in ['light.a', 'lock.a', 'cover.a', 'media_player.a']) {
        for (final level in ['a', 'b', 'c', 'd']) {
          for (final MapEntry(key: voice, value: input) in voices.entries) {
            final access = AccessContext.lockedFor(input);
            final want = switch (level) {
              'a' => a,
              'b' => voice == 'erkannt' ? a : u,
              _ => u,
            };
            expect(
              haDecide(
                _e(id, level: level),
                locked: access.locked,
                speakerRecognized: access.speakerRecognized,
              ),
              want,
              reason: '$id $level $voice',
            );
          }
        }
      }
    });
    test('Standard: Licht B fragt Stimme, Schloss D nie, auch erkannt', () {
      const voice = true;
      expect(
        haDecide(_e('light.a'), locked: true, speakerRecognized: voice),
        a,
      );
      expect(haDecide(_e('light.a'), locked: true), u);
      expect(
        haDecide(_e('media_player.a'), locked: true, speakerRecognized: voice),
        a,
      );
      expect(haDecide(_e('lock.a'), locked: true, speakerRecognized: voice), u);
      expect(
        haDecide(
          _e('alarm_control_panel.a'),
          locked: true,
          speakerRecognized: voice,
        ),
        u,
      );
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
      // Just synced: no background comparison races with the test.
      FakeHaEntityStore(devices)..synced = DateTime.now(),
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

    test('ruhiges Rollo, Licht B und Schloss A laufen auch über ha__call_secure (nur strenger)', () async {
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
      final light = await run(h, 'ha__call_secure', 'light.kitchen', 'turn_on');
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
    });

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

    group('gesperrt (L2/L3, Stimme je Aufruf)', () {
      ToolContext lockedCtx({bool voice = false}) => ToolContext(
        sessionId: 's1',
        clock: FixedClock(DateTime.utc(2026, 10, 13, 12)),
        locale: 'de-DE',
        timeZone: 'Europe/Berlin',
        access: AccessContext(locked: true, speakerRecognized: voice),
      );
      Future<ToolOutcome> runLocked(
        HaIntegration h,
        String tool,
        String id,
        String s, {
        bool voice = false,
      }) => h.tools.singleWhere((t) => t.name == tool).execute({
        'entity': id,
        'service': s,
      }, lockedCtx(voice: voice));

      test('Licht auf A läuft', () async {
        final h = ha([_e('light.kitchen', level: 'a')]);
        final r = await runLocked(h, 'ha__call', 'light.kitchen', 'turn_on');
        expect(r.isError, isFalse, reason: r.text);
        expect(api.calls.single.service, 'turn_on');
      });

      for (final (name, entity, level) in [
        ('Licht B (Standard)', 'light.kitchen', null),
        ('Licht auf C', 'light.kitchen', 'c'),
        ('Rollo C', 'cover.living', 'c'),
        ('Schloss D (Standard)', 'lock.front', null),
        ('Licht auf D', 'light.kitchen', 'd'),
      ]) {
        test(
          '$name: Entsperren nötig, Home Assistant nie aufgerufen',
          () async {
            api.set(entity, 'off', const {});
            final h = ha([_e(entity, level: level)]);
            final r = await runLocked(h, 'ha__call', entity, 'turn_on');
            expect(r.isError, isTrue);
            expect(r.summary, 'Entsperren nötig');
            expect(api.calls, isEmpty);
          },
        );
      }

      test('erkannte Stimme: Licht auf B läuft', () async {
        final h = ha([_e('light.kitchen', level: 'b')]);
        final r = await runLocked(
          h,
          'ha__call',
          'light.kitchen',
          'turn_on',
          voice: true,
        );
        expect(r.isError, isFalse, reason: r.text);
        expect(api.calls, hasLength(1));
      });

      test('Licht B (Standard) mit fremder Stimme: Entsperren nötig', () async {
        final h = ha([_e('light.kitchen')]);
        final r = await runLocked(h, 'ha__call', 'light.kitchen', 'turn_on');
        expect(r.isError, isTrue);
        expect(r.summary, 'Entsperren nötig');
        expect(api.calls, isEmpty);
        final ok = await runLocked(
          h,
          'ha__call',
          'light.kitchen',
          'turn_on',
          voice: true,
        );
        expect(ok.isError, isFalse, reason: ok.text);
        expect(api.calls, hasLength(1), reason: 'Standard B: erkannte Stimme');
      });

      test(
        'Schloss D und Szene mit Schloss laufen nie, auch erkannt',
        () async {
          api.set('lock.front', 'locked', const {});
          final h = ha([_e('lock.front')]);
          final r = await runLocked(
            h,
            'ha__call',
            'lock.front',
            'unlock',
            voice: true,
          );
          expect(r.summary, 'Entsperren nötig');
          expect(api.calls, isEmpty);
        },
      );

      test('ha__call_secure gesperrt nie, auch nicht Schloss auf A', () async {
        final h = ha([_e('lock.front', level: 'a'), _e('light.k', level: 'a')]);
        for (final (id, s) in [
          ('lock.front', 'lock'),
          ('light.k', 'turn_on'),
        ]) {
          final r = await runLocked(h, 'ha__call_secure', id, s);
          expect(r.isError, isTrue, reason: id);
          expect(r.summary, 'Entsperren nötig');
        }
        expect(api.calls, isEmpty);
      });

      test(
        'Promptabschnitt listet nur erlaubte Geräte, ohne list_entities',
        () async {
          final h = ha([
            _e('light.kitchen', name: 'Küchenlicht', level: 'a'),
            _e('light.hall', name: 'Flurampel'),
            _e('lock.front', name: 'Haustürschloss'),
            _e('switch.coffee', name: 'Kaffeesteckdose'),
          ]);
          final section = await h.tools
              .whereType<PromptContributor>()
              .first
              .promptSection(
                'Licht an',
                access: AccessContext.lockedUnknownVoice,
              );
          expect(section, isNotNull);
          expect(section, contains('Küchenlicht'));
          expect(section, isNot(contains('Flurampel')));
          expect(section, isNot(contains('Haustürschloss')));
          expect(section, isNot(contains('Kaffeesteckdose')));
          expect(section, isNot(contains('ha__list_entities')));
          expect(
            RegExp('\\((light|lock|switch)\\)').allMatches(section!),
            hasLength(1),
          );
          // Entsperrt stehen die Namen (Gegenprobe, der Test prüft etwas).
          final open = await h.tools
              .whereType<PromptContributor>()
              .first
              .promptSection('Licht an');
          expect(open, contains('Flurampel'));
        },
      );

      test('anyAllowedWhileLocked: nur wenn ein Gerät erlaubt ist', () async {
        expect(
          await ha([_e('light.k')])
              .anyAllowedWhileLocked(AccessContext.lockedUnknownVoice),
          isFalse,
        );
        expect(
          await ha([_e('light.k', level: 'a')])
              .anyAllowedWhileLocked(AccessContext.lockedUnknownVoice),
          isTrue,
        );
        expect(
          await ha([_e('light.k')])
              .anyAllowedWhileLocked(AccessContext.unlocked),
          isTrue,
        );
      });
    });
  });
}
