// WP154 L2: Gesperrt entscheidet allein die Tabelle levelAccess(locked: true).
import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import 'locked_tools.dart';

const _locked = AccessContext.lockedUnknownVoice;
const _voice = AccessContext(locked: true, speakerRecognized: true);

final _read = FakeTool(name: 'p__read');
final _write = FakeTool(name: 'p__write', risk: RiskLevel.write);
final _external = FakeTool(name: 'p__send', risk: RiskLevel.external);

void main() {
  group('Standard gesperrt = heute (nichts läuft)', () {
    for (final tool in [_read, _write, _external]) {
      test('${tool.risk.name} gesperrt → Entsperren', () {
        expect(
          RiskPolicy().decide(tool, 's', access: _locked),
          PolicyDecision.unlock,
        );
      });
    }
    test('ohne access gilt „entsperrt“ wie bisher', () {
      expect(RiskPolicy().decide(_write, 's'), PolicyDecision.allow);
    });
  });

  group('Tabelle je Stufe × Stimme (gesperrt)', () {
    final cases = <(SecurityLevel, AccessContext, PolicyDecision)>[
      (SecurityLevel.a, _locked, PolicyDecision.allow),
      (SecurityLevel.a, _voice, PolicyDecision.allow),
      (SecurityLevel.b, _locked, PolicyDecision.unlock),
      (SecurityLevel.b, _voice, PolicyDecision.allow),
      (SecurityLevel.c, _locked, PolicyDecision.unlock),
      (SecurityLevel.c, _voice, PolicyDecision.unlock),
      (SecurityLevel.d, _locked, PolicyDecision.unlock),
      (SecurityLevel.d, _voice, PolicyDecision.unlock),
    ];
    for (final tool in [_read, _external]) {
      for (final (level, access, expected) in cases) {
        test('${tool.risk.name} auf ${level.name}, Stimme '
            '${access.speakerRecognized} → ${expected.action.name}', () {
          final p = RiskPolicy()..setLevel(tool.name, level);
          expect(p.decide(tool, 's', access: access), expected);
        });
      }
    }
  });

  group('Vorbehalte bleiben gesperrt', () {
    test('deaktiviertes Tool bleibt verweigert, auch auf A', () {
      final p = RiskPolicy()
        ..setLevel('p__read', SecurityLevel.a)
        ..setOverride('p__read', PolicyAction.deny);
      expect(
        p.decide(_read, 's', access: _locked),
        PolicyDecision.deny(RiskPolicy.deniedReason),
      );
    });

    test('„immer bestätigen“-Override auf A heißt gesperrt: Entsperren', () {
      final p = RiskPolicy()
        ..setLevel('p__read', SecurityLevel.a)
        ..setOverride('p__read', PolicyAction.confirm);
      expect(p.decide(_read, 's', access: _locked), PolicyDecision.unlock);
    });

    test('Sitzungssperre external schlägt Stufe A', () {
      final p = RiskPolicy()
        ..setLevel('p__send', SecurityLevel.a)
        ..lockExternal('s');
      expect(
        p.decide(_external, 's', access: _locked),
        PolicyDecision.deny(RiskPolicy.lockedReason),
      );
    });
  });

  group('Standardstufe des Tools (DefaultLevelTool)', () {
    final torch = LevelFake(
      FakeTool(name: 'f__on', risk: RiskLevel.write),
      SecurityLevel.a,
    );

    test('A gesperrt erlaubt, entsperrt wie bisher', () {
      final p = RiskPolicy();
      expect(RiskPolicy.defaultLevelOf(torch), SecurityLevel.a);
      expect(p.decide(torch, 's', access: _locked), PolicyDecision.allow);
      expect(p.decide(torch, 's'), PolicyDecision.allow);
    });

    test('Nutzerstufe schlägt den Standard (D → Entsperren)', () {
      final p = RiskPolicy()..setLevel('f__on', SecurityLevel.d);
      expect(p.decide(torch, 's', access: _locked), PolicyDecision.unlock);
    });

    test('Tool ohne Standardstufe nutzt die des Risikos', () {
      expect(RiskPolicy.defaultLevelOf(_write), SecurityLevel.c);
      expect(RiskPolicy.defaultLevelOf(_external), SecurityLevel.d);
    });
  });

  group('Tool mit Stufe je Gerät (LevelPerDeviceTool)', () {
    final ha = PerDeviceFake(FakeTool(name: 'h__call', risk: RiskLevel.write));

    test('gesperrt durchgelassen, das Tool entscheidet selbst', () {
      expect(
        RiskPolicy().decide(ha, 's', access: _locked),
        PolicyDecision.allow,
      );
    });

    test('gespeichertes D (altes „Immer bestätigen“): nie lockerer', () {
      final p = RiskPolicy()..setLevel('h__call', SecurityLevel.d);
      expect(p.decide(ha, 's').action, PolicyAction.confirm);
      expect(p.decide(ha, 's', access: _locked), PolicyDecision.unlock);
      expect(p.decide(ha, 's', access: _voice), PolicyDecision.unlock);
    });

    test('gespeichertes A auf dem Gerätetool: gesperrt durchgelassen', () {
      final p = RiskPolicy()..setLevel('h__call', SecurityLevel.a);
      expect(p.decide(ha, 's', access: _locked), PolicyDecision.allow);
    });

    test('deaktiviert bleibt verweigert', () {
      final p = RiskPolicy()..setOverride('h__call', PolicyAction.deny);
      expect(p.decide(ha, 's', access: _locked).action, PolicyAction.deny);
    });
  });

  test(
    'PolicyDecision.unlock trägt den Text und unterscheidet sich vom deny',
    () {
      expect(PolicyDecision.unlock.action, PolicyAction.deny);
      expect(PolicyDecision.unlock.needsUnlock, isTrue);
      expect(PolicyDecision.unlock.reason, contains('Entsperren nötig'));
      expect(
        PolicyDecision.unlock,
        isNot(PolicyDecision.deny(RiskPolicy.unlockReason)),
      );
    },
  );
}
