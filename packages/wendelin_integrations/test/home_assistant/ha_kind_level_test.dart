import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Level per device kind (WP160, ADR 0022): order own level > kind >
/// default, and what a kind never loosens.
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

HaKindLevels _k(Map<String, String> m) => HaKindLevels(m);

LevelAccess _lockedNoVoice(
  HaEntity e,
  HaKindLevels k, {
  HaState? state,
  Set<String> critical = const {},
}) => haDecide(e, kinds: k, state: state, criticalIds: critical, locked: true);

void main() {
  group('Art-Stufe', () {
    test(
      'Licht auf A: gesperrt ohne Stimme erlaubt, ohne Art B -> entsperren',
      () {
        final e = _e('light.a');
        expect(_lockedNoVoice(e, _k({'light': 'a'})), LevelAccess.allowed);
        expect(_lockedNoVoice(e, const HaKindLevels()), LevelAccess.unlock);
      },
    );

    test('Art wirkt je Art: Medien, Schalter, Heizung, Szene', () {
      const k = HaKindLevels({
        'media': 'a',
        'switch': 'a',
        'climate': 'd',
        'scene': 'a',
      });
      expect(haEffectiveLevel(_e('media_player.a'), kinds: k), SecurityLevel.a);
      expect(haEffectiveLevel(_e('switch.a'), kinds: k), SecurityLevel.a);
      expect(haEffectiveLevel(_e('climate.a'), kinds: k), SecurityLevel.d);
      expect(
        haEffectiveLevel(_e('scene.a'), kinds: k, scene: HaSceneKind.safe),
        SecurityLevel.a,
      );
      expect(haEffectiveLevel(_e('light.a'), kinds: k), SecurityLevel.b);
    });

    test('eigene Gerätestufe C schlägt Art A', () {
      expect(
        haEffectiveLevel(_e('light.a', level: 'c'), kinds: _k({'light': 'a'})),
        SecurityLevel.c,
      );
    });

    test('altes alwaysConfirm schlägt Art A (wie eigene Stufe D)', () {
      final e = _e('light.a', confirm: true);
      expect(haEffectiveLevel(e, kinds: _k({'light': 'a'})), SecurityLevel.d);
      expect(_lockedNoVoice(e, _k({'light': 'a'})), LevelAccess.unlock);
    });

    test('kaputter Art-Wert ist D, fehlender ist Standard', () {
      for (final bad in ['x', '', 'A', '?']) {
        expect(
          haEffectiveLevel(_e('light.a'), kinds: _k({'light': bad})),
          SecurityLevel.d,
          reason: bad,
        );
      }
      expect(haEffectiveLevel(_e('light.a'), kinds: _k({})), SecurityLevel.b);
      expect(
        haEffectiveLevel(_e('light.a'), kinds: const HaKindLevels.broken()),
        SecurityLevel.d,
      );
    });

    test('Schloss und Alarm bleiben D, Art-Schlüssel hin oder her', () {
      final k = _k({'lock': 'a', 'alarm_control_panel': 'a', 'light': 'a'});
      expect(haEffectiveLevel(_e('lock.a'), kinds: k), SecurityLevel.d);
      expect(
        haEffectiveLevel(_e('alarm_control_panel.a'), kinds: k),
        SecurityLevel.d,
      );
    });

    test(
      'Rollo-Art A lockert Garage, Tor, Tür und unbekannte Klasse nicht',
      () {
        final k = _k({'cover': 'a'});
        for (final cls in ['garage', 'gate', 'door', 'damper', null]) {
          final e = _e('cover.a', cls: cls);
          final live = _s('cover.a', {'device_class': ?cls});
          expect(
            haDecide(e, kinds: k, state: live, locked: true),
            LevelAccess.unlock,
            reason: '$cls',
          );
          expect(haDecide(e, kinds: k, state: live), LevelAccess.confirm);
        }
        // Ohne Live-Zustand ebenfalls D.
        expect(
          haDecide(_e('cover.a', cls: 'blind'), kinds: k),
          LevelAccess.confirm,
        );
      },
    );

    test('Rollo-Art A gilt für Rollo (Live-Klasse blind)', () {
      final e = _e('cover.a', cls: 'blind');
      final live = _s('cover.a', {'device_class': 'blind'});
      expect(
        haDecide(e, kinds: _k({'cover': 'a'}), state: live, locked: true),
        LevelAccess.allowed,
      );
      // Live-Klasse Garage trotz gespeichertem blind: D.
      expect(
        haDecide(
          e,
          kinds: _k({'cover': 'a'}),
          state: _s('cover.a', {'device_class': 'garage'}),
          locked: true,
        ),
        LevelAccess.unlock,
      );
    });

    test('Szene mit Schloss bleibt D, auch bei Art A', () {
      final k = _k({'scene': 'a'});
      final scene = _e('scene.a');
      final live = _s('scene.a', {
        'entity_id': ['light.x', 'lock.front'],
      });
      expect(haDecide(scene, kinds: k, state: live), LevelAccess.confirm);
      expect(
        haDecide(scene, kinds: k, state: live, locked: true),
        LevelAccess.unlock,
      );
      // Mitglied auf D über Art: Szene kritisch.
      final live2 = _s('scene.a', {
        'entity_id': ['light.x'],
      });
      expect(
        haDecide(scene, kinds: k, state: live2, criticalIds: {'light.x'}),
        LevelAccess.confirm,
      );
    });

    test('Szene ohne Mitglieder ist höchstens C, strengere Art gilt', () {
      final scene = _e('scene.a');
      expect(
        haEffectiveLevel(scene, kinds: _k({'scene': 'a'})),
        SecurityLevel.c,
      );
      expect(
        haEffectiveLevel(scene, kinds: _k({'scene': 'd'})),
        SecurityLevel.d,
      );
    });

    test('Art-Wert falscher Typ im JSON ist D, Nicht-Map ist kaputt', () {
      final k = HaKindLevels.fromJson({'light': 5, 'media': 'a'});
      expect(k.levelOf(HaKind.light), SecurityLevel.d);
      expect(k.levelOf(HaKind.media), SecurityLevel.a);
      expect(k.levelOf(HaKind.climate), isNull);
      expect(HaKindLevels.fromJson([1]).isBroken, isTrue);
      expect(
        HaKindLevels.fromJson(null).levelOf(HaKind.light),
        SecurityLevel.d,
      );
    });

    test('withLevel auf kaputtem Speicher hält die anderen Arten auf D', () {
      final k = const HaKindLevels.broken().withLevel(
        HaKind.light,
        SecurityLevel.a,
      );
      expect(k.levelOf(HaKind.light), SecurityLevel.a);
      expect(k.levelOf(HaKind.media), SecurityLevel.d);
      expect(k.withLevel(HaKind.light, null).levelOf(HaKind.light), isNull);
    });
  });

  group('Art-Stufe in Integration, Prompt, Schnellpfad', () {
    Future<HaIntegration> integ(FakeHaEntityStore store) async =>
        HaIntegration(FakeHaApi(), FakeHaSecrets(), store);

    Future<String?> section(HaIntegration ha, AccessContext access) => ha.tools
        .whereType<PromptContributor>()
        .single
        .promptSection('Licht', access: access);

    test('anyAllowedWhileLocked und Promptabschnitt folgen der Art', () async {
      final store = FakeHaEntityStore([_e('light.a')])..synced = DateTime.now();
      final ha = await integ(store);
      const locked = AccessContext(locked: true);
      expect(await ha.anyAllowedWhileLocked(locked), isFalse);
      expect(await section(ha, locked), isNull);
      store.kinds = _k({'light': 'a'});
      expect(await ha.anyAllowedWhileLocked(locked), isTrue);
      expect(await section(ha, locked), contains('light'));
    });

    test('kaputter Speicher der Arten: nichts lockert', () async {
      final store = FakeHaEntityStore([_e('light.a')])
        ..kinds = const HaKindLevels.broken();
      final ha = await integ(store);
      expect(
        await ha.anyAllowedWhileLocked(
          const AccessContext(locked: true, speakerRecognized: true),
        ),
        isFalse,
      );
    });
  });
}
