// WP201 / ADR 0023: after foreign content that came only from the MCP server
// X, a tool of X skips the minimum confirmation; every other origin keeps it.
import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

/// Stands in for an `McpTool` (wendelin_tools must not depend on
/// wendelin_mcp): a network tool that names its server.
final class _ServerTool implements Tool, ContentOriginAware, LevelFixedTool {
  _ServerTool(
    this.serverId, {
    this.risk = RiskLevel.write,
    this.levelFixed = false,
  });

  final String serverId;

  @override
  final RiskLevel risk;

  @override
  final bool levelFixed;

  @override
  ContentOrigin get contentOrigin => ContentOrigin.server(serverId);

  @override
  String get name => 'mcp_$serverId';
  @override
  String get description => 'd';
  @override
  Map<String, Object?> get inputSchema => const {'type': 'object'};
  @override
  Future<ToolOutcome> execute(Map<String, Object?> args, ToolContext ctx) =>
      throw UnimplementedError();
  @override
  String describeForConfirmation(Map<String, Object?> args) => 'x';
}

const _allow = PolicyDecision.allow;
const _confirm = PolicyDecision.confirm;
const _unlock = PolicyDecision.unlock;

void main() {
  final x = _ServerTool('X');
  const fromX = ContentOrigin.server('X');
  const fromY = ContentOrigin.server('Y');

  RiskPolicy levelA(Tool t) => RiskPolicy()..setLevel(t.name, SecurityLevel.a);

  group('Stufe „Ohne Nachfrage“, Tool von X', () {
    test('Inhalte nur von X: läuft ohne Nachfrage', () {
      expect(
        levelA(x).decide(x, 's', foreignContent: true, foreignOrigin: fromX),
        _allow,
      );
    });
    test('Inhalte von Y: bestätigt', () {
      expect(
        levelA(x).decide(x, 's', foreignContent: true, foreignOrigin: fromY),
        _confirm,
      );
    });
    test('unbekannte Herkunft: bestätigt', () {
      expect(
        levelA(x).decide(
          x,
          's',
          foreignContent: true,
          foreignOrigin: ContentOrigin.unknown,
        ),
        _confirm,
      );
    });
    test('gemischte Herkunft (X und Y): bestätigt', () {
      expect(
        levelA(x).decide(
          x,
          's',
          foreignContent: true,
          foreignOrigin: fromX.merge(fromY),
        ),
        _confirm,
      );
    });
    test('Fremdes ohne Herkunftsangabe (Standard): bestätigt', () {
      expect(levelA(x).decide(x, 's', foreignContent: true), _confirm);
    });
    test('Herkunft X, aber nichts Fremdes gesehen: unverändert frei', () {
      expect(levelA(x).decide(x, 's', foreignOrigin: fromX), _allow);
    });
  });

  test('Tool von Y nach Inhalten von X: bestätigt', () {
    final y = _ServerTool('Y');
    expect(
      levelA(y).decide(y, 's', foreignContent: true, foreignOrigin: fromX),
      _confirm,
    );
  });

  test('Tool ohne Herkunftsangabe nach Inhalten von X: bestätigt', () {
    final net = FakeTool(name: 'p__net');
    final p = RiskPolicy()..setLevel(net.name, SecurityLevel.a);
    expect(
      p.decide(net, 's', foreignContent: true, foreignOrigin: fromX),
      _confirm,
    );
  });

  test('Tool ohne Herkunftsangabe und unbekannte Herkunft: bestätigt '
      '(unknown ist nie „gleicher Server“)', () {
    final net = FakeTool(name: 'p__net');
    final p = RiskPolicy()..setLevel(net.name, SecurityLevel.a);
    expect(
      p.decide(
        net,
        's',
        foreignContent: true,
        foreignOrigin: ContentOrigin.unknown,
      ),
      _confirm,
    );
  });

  group('andere Schutzstufen unverändert', () {
    test('gesperrtes Gerät: Y → X wartet auf Entsperren', () {
      expect(
        levelA(x).decide(
          x,
          's',
          access: AccessContext.lockedUnknownVoice,
          foreignContent: true,
          foreignOrigin: fromY,
        ),
        _unlock,
      );
    });
    test('gesperrtes Gerät: X → X wie ohne Fremdes (Tabelle entscheidet)', () {
      expect(
        levelA(x).decide(
          x,
          's',
          access: AccessContext.lockedUnknownVoice,
          foreignContent: true,
          foreignOrigin: fromX,
        ),
        // Level A is allowed on a locked device only where the table says so;
        // the exemption must not loosen it beyond the plain level.
        levelA(x).decide(x, 's', access: AccessContext.lockedUnknownVoice),
      );
    });
    test('Stufe D (Alle bestätigen) bleibt bestätigt', () {
      final p = RiskPolicy()..setLevel(x.name, SecurityLevel.d);
      expect(
        p.decide(x, 's', foreignContent: true, foreignOrigin: fromX),
        _confirm,
      );
    });
    test('„Alle Tools bestätigen“ des Servers (levelFixed) bleibt', () {
      final fixed = _ServerTool(
        'X',
        risk: RiskLevel.external,
        levelFixed: true,
      );
      expect(
        RiskPolicy().decide(
          fixed,
          's',
          foreignContent: true,
          foreignOrigin: fromX,
        ),
        _confirm,
      );
    });
    test('Override confirm bleibt, Override deny bleibt', () {
      final c = RiskPolicy(overrides: {x.name: PolicyAction.confirm})
        ..setLevel(x.name, SecurityLevel.a);
      expect(
        c.decide(x, 's', foreignContent: true, foreignOrigin: fromX),
        _confirm,
      );
      final d = RiskPolicy(overrides: {x.name: PolicyAction.deny});
      expect(
        d.decide(x, 's', foreignContent: true, foreignOrigin: fromX).action,
        PolicyAction.deny,
      );
    });
    test('Sitzungssperre + Inhalte von X: Tool von X weiter verweigert', () {
      // Deliberate: the locked session means a failed TEE receipt; sending
      // data to X is exfiltration to the server whose content we hold.
      final p = levelA(x)..lockExternal('s');
      expect(
        p.decide(x, 's', foreignContent: true, foreignOrigin: fromX),
        PolicyDecision.deny(RiskPolicy.networkLockedReason),
      );
    });
    test('Sitzungssperre ohne Fremdes: read-Tool von X unverändert frei', () {
      final p = levelA(x)..lockExternal('s');
      expect(p.decide(x, 's'), _allow);
    });
  });

  test('Executor-effectiveRisk spiegelt die Ausnahme', () {
    final p = levelA(x);
    final e = ToolExecutor(catalog: FakeToolCatalog([x]), policy: p);
    expect(
      e.effectiveRisk(x, 's', foreignContent: true, foreignOrigin: fromX),
      RiskLevel.write,
    );
    expect(
      e.effectiveRisk(x, 's', foreignContent: true, foreignOrigin: fromY),
      RiskLevel.external,
    );
  });
}
