// WP154: riskPolicyProvider setzt die Stufen je Tool (ADR 0022).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/agent_providers.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../support/test_env.dart';

final _read = FakeTool(name: 'p__read');
final _write = FakeTool(name: 'p__write', risk: RiskLevel.write);
final _external = FakeTool(name: 'p__send', risk: RiskLevel.external);
final _haCall = FakeTool(name: 'ha__call', risk: RiskLevel.write);

_Handle _make(ToolPrefs prefs) {
  final env = TestEnv(startup: StartupSettings(toolPrefs: prefs));
  final c = env.container();
  addTearDown(c.dispose);
  return _Handle(c);
}

class _Handle {
  _Handle(this.c);
  final ProviderContainer c;
  RiskPolicy get policy => c.read(riskPolicyProvider);
  void set(ToolPrefs p) => c.read(toolPrefsProvider.notifier).set(p);
}

void main() {
  test('ohne Einträge gelten die Standardstufen', () {
    final p = _make(const ToolPrefs()).policy;
    expect(p.decide(_read, 's'), PolicyDecision.allow);
    expect(p.decide(_write, 's'), PolicyDecision.allow);
    expect(p.decide(_external, 's'), PolicyDecision.confirm);
  });

  test('Stufe lockert external und verschärft read, Änderung wirkt sofort', () {
    final h = _make(const ToolPrefs());
    final p = h.policy;
    h.set(
      const ToolPrefs(
        levels: {'p__send': 'c', 'p__read': 'd', 'p__write': 'a'},
      ),
    );
    expect(p.decide(_external, 's'), PolicyDecision.allow);
    expect(p.decide(_read, 's'), PolicyDecision.confirm);
    expect(p.decide(_write, 's'), PolicyDecision.allow);
    // Zurück auf Standard: external fragt wieder, read nicht mehr.
    h.set(const ToolPrefs());
    expect(p.decide(_external, 's'), PolicyDecision.confirm);
    expect(p.decide(_read, 's'), PolicyDecision.allow);
    expect(p.levelFor('p__send'), isNull);
  });

  test('altes „Immer nachfragen“ gilt als D, die Stufe hat Vorrang', () {
    final p = _make(
      const ToolPrefs(
        alwaysConfirm: {'p__write', 'p__read'},
        levels: {'p__read': 'c'},
      ),
    ).policy;
    expect(p.decide(_write, 's'), PolicyDecision.confirm);
    expect(p.decide(_read, 's'), PolicyDecision.allow);
  });

  test('ungültige Stufe ist D (fail-closed)', () {
    final p = _make(
      const ToolPrefs(levels: {'p__read': 'z', 'p__write': '', 'p__send': 'A'}),
    ).policy;
    expect(p.decide(_read, 's'), PolicyDecision.confirm);
    expect(p.decide(_write, 's'), PolicyDecision.confirm);
    expect(p.decide(_external, 's'), PolicyDecision.confirm);
  });

  test('ha__call: eine Tool-Stufe wirkt zusätzlich, das alte „immer '
      'bestätigen“ ebenso (D)', () {
    final strict = _make(const ToolPrefs(levels: {'ha__call': 'd'})).policy;
    expect(strict.levelFor('ha__call'), SecurityLevel.d);
    expect(strict.decide(_haCall, 's'), PolicyDecision.confirm);
    final c = _make(const ToolPrefs(levels: {'ha__call': 'c'})).policy;
    expect(c.decide(_haCall, 's'), PolicyDecision.allow);
    expect(
      c.decide(_haCall, 's', access: AccessContext.lockedUnknownVoice),
      PolicyDecision.unlock,
    );
    final legacy = _make(const ToolPrefs(alwaysConfirm: {'ha__call'})).policy;
    expect(legacy.decide(_haCall, 's'), PolicyDecision.confirm);
  });

  test('lockExternal verweigert trotz gelockerter Stufe', () {
    final p = _make(const ToolPrefs(levels: {'p__send': 'a'})).policy;
    expect(p.decide(_external, 's'), PolicyDecision.allow);
    p.lockExternal('s');
    expect(p.decide(_external, 's').action, PolicyAction.deny);
  });
}
