import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

final _read = FakeTool(name: 'p__read');
final _write = FakeTool(name: 'p__write', risk: RiskLevel.write);
final _external = FakeTool(name: 'p__send', risk: RiskLevel.external);

void main() {
  test('Standard je Stufe', () {
    final p = RiskPolicy();
    expect(p.decide(_read, 's'), PolicyDecision.allow);
    expect(p.decide(_write, 's'), PolicyDecision.allow);
    expect(p.decide(_external, 's'), PolicyDecision.confirm);
  });

  group('Overrides verschärfen nur', () {
    final cases = <(Tool, PolicyAction, PolicyAction)>[
      (_read, PolicyAction.allow, PolicyAction.allow),
      (_read, PolicyAction.confirm, PolicyAction.confirm),
      (_read, PolicyAction.deny, PolicyAction.deny),
      (_write, PolicyAction.allow, PolicyAction.allow),
      (_write, PolicyAction.confirm, PolicyAction.confirm),
      (_write, PolicyAction.deny, PolicyAction.deny),
      (_external, PolicyAction.allow, PolicyAction.confirm),
      (_external, PolicyAction.confirm, PolicyAction.confirm),
      (_external, PolicyAction.deny, PolicyAction.deny),
    ];
    for (final (tool, override, expected) in cases) {
      test('${tool.risk.name} + ${override.name} → ${expected.name}', () {
        final p = RiskPolicy(overrides: {tool.name: override});
        expect(p.decide(tool, 's').action, expected);
      });
    }
  });

  test('external-Override „allow“ per setOverride lockert nicht', () {
    final p = RiskPolicy()..setOverride('p__send', PolicyAction.allow);
    expect(p.overrideFor('p__send'), PolicyAction.allow);
    expect(p.decide(_external, 's'), PolicyDecision.confirm);
  });

  group('Stufe je Tool (WP154)', () {
    final cases = <(Tool, SecurityLevel, PolicyAction)>[
      (_read, SecurityLevel.a, PolicyAction.allow),
      (_read, SecurityLevel.b, PolicyAction.allow),
      (_read, SecurityLevel.c, PolicyAction.allow),
      (_read, SecurityLevel.d, PolicyAction.confirm),
      (_external, SecurityLevel.a, PolicyAction.allow),
      (_external, SecurityLevel.b, PolicyAction.allow),
      (_external, SecurityLevel.c, PolicyAction.allow),
      (_external, SecurityLevel.d, PolicyAction.confirm),
    ];
    for (final (tool, level, expected) in cases) {
      test('${tool.risk.name} auf ${level.name} → ${expected.name}', () {
        final p = RiskPolicy()..setLevel(tool.name, level);
        expect(p.decide(tool, 's').action, expected);
      });
    }

    test('Stufe lockert external; Deaktivieren und Sperre bleiben', () {
      final p = RiskPolicy()
        ..setLevel('p__send', SecurityLevel.a)
        ..setOverride('p__send', PolicyAction.deny);
      expect(p.decide(_external, 's').action, PolicyAction.deny);
      final q = RiskPolicy()
        ..setLevel('p__send', SecurityLevel.a)
        ..lockExternal('s');
      expect(q.decide(_external, 's').action, PolicyAction.deny);
    });

    test('clearLevel stellt den Standard wieder her', () {
      final p = RiskPolicy()..setLevel('p__send', SecurityLevel.a);
      p.clearLevel('p__send');
      expect(p.levelFor('p__send'), isNull);
      expect(p.decide(_external, 's'), PolicyDecision.confirm);
    });

    test('Standardstufen je Risiko', () {
      expect(RiskPolicy.defaultLevelFor(RiskLevel.read), SecurityLevel.c);
      expect(RiskPolicy.defaultLevelFor(RiskLevel.write), SecurityLevel.c);
      expect(RiskPolicy.defaultLevelFor(RiskLevel.external), SecurityLevel.d);
    });
  });

  test('clearOverride stellt den Standard wieder her', () {
    final p = RiskPolicy()..setOverride('p__read', PolicyAction.deny);
    expect(p.decide(_read, 's').action, PolicyAction.deny);
    p.clearOverride('p__read');
    expect(p.overrideFor('p__read'), isNull);
    expect(p.decide(_read, 's'), PolicyDecision.allow);
  });

  test('Override gilt nur für sein Tool', () {
    final p = RiskPolicy(overrides: {'p__other': PolicyAction.deny});
    expect(p.decide(_read, 's'), PolicyDecision.allow);
  });

  test('deny hat lesbaren Grund', () {
    final p = RiskPolicy(overrides: {'p__read': PolicyAction.deny});
    expect(p.decide(_read, 's'), PolicyDecision.deny(RiskPolicy.deniedReason));
  });

  group('lockExternal', () {
    test('sperrt external der Session, nicht read/write', () {
      final p = RiskPolicy()..lockExternal('s1');
      expect(p.isExternalLocked('s1'), isTrue);
      expect(
        p.decide(_external, 's1'),
        PolicyDecision.deny(RiskPolicy.lockedReason),
      );
      expect(p.decide(_read, 's1'), PolicyDecision.allow);
      expect(p.decide(_write, 's1'), PolicyDecision.allow);
    });

    test('andere Session nicht betroffen', () {
      final p = RiskPolicy()..lockExternal('s1');
      expect(p.isExternalLocked('s2'), isFalse);
      expect(p.decide(_external, 's2'), PolicyDecision.confirm);
    });

    test('Sperre schlägt auch einen confirm-Override', () {
      final p = RiskPolicy(overrides: {'p__send': PolicyAction.confirm})
        ..lockExternal('s1');
      expect(p.decide(_external, 's1').action, PolicyAction.deny);
    });
  });

  test('atLeast wählt die strengere Aktion', () {
    expect(
      PolicyAction.allow.atLeast(PolicyAction.confirm),
      PolicyAction.confirm,
    );
    expect(PolicyAction.deny.atLeast(PolicyAction.confirm), PolicyAction.deny);
    expect(
      PolicyAction.confirm.atLeast(PolicyAction.confirm),
      PolicyAction.confirm,
    );
  });

  test('PolicyDecision Gleichheit und toString', () {
    expect(PolicyDecision.deny('a'), PolicyDecision.deny('a'));
    expect(PolicyDecision.deny('a'), isNot(PolicyDecision.deny('b')));
    expect(
      PolicyDecision.deny('a').hashCode,
      PolicyDecision.deny('a').hashCode,
    );
    expect(PolicyDecision.allow.toString(), 'PolicyDecision(allow)');
    expect(PolicyDecision.deny('x').toString(), 'PolicyDecision(deny: x)');
  });
}
