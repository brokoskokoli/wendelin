// WP157 / ADR 0023: after foreign content a tool with a network target is
// asked about; a tool without one (NoNetworkTarget) is unchanged. Stricter
// wins: level A does not lift the minimum.
import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

/// A [FakeTool] that declares it never carries arguments to a network
/// target.
final class _NoNet implements Tool, NoNetworkTarget {
  _NoNet(this.inner);

  final FakeTool inner;

  @override
  String get name => inner.name;
  @override
  String get description => inner.description;
  @override
  Map<String, Object?> get inputSchema => inner.inputSchema;
  @override
  RiskLevel get risk => inner.risk;
  @override
  Future<ToolOutcome> execute(Map<String, Object?> args, ToolContext ctx) =>
      inner.execute(args, ctx);
  @override
  String describeForConfirmation(Map<String, Object?> args) =>
      inner.describeForConfirmation(args);
}

const _allow = PolicyDecision.allow;
const _confirm = PolicyDecision.confirm;
const _unlock = PolicyDecision.unlock;

void main() {
  // Unmarked FakeTool = network target (fail-closed default).
  final net = FakeTool(name: 'p__net');
  final noNet = _NoNet(FakeTool(name: 'p__local'));

  group('entsperrt: Tabelle fremd × Netzziel × Stufe', () {
    // (fremd, Netzziel, Stufe, erwartet)
    final cases = <(bool, bool, SecurityLevel, PolicyDecision)>[
      for (final level in SecurityLevel.values) ...[
        (false, true, level, level == SecurityLevel.d ? _confirm : _allow),
        (false, false, level, level == SecurityLevel.d ? _confirm : _allow),
        // Netzziel nach Fremdem: mindestens Rückfrage, Stufe A hebt nicht auf.
        (true, true, level, _confirm),
        (true, false, level, level == SecurityLevel.d ? _confirm : _allow),
      ],
    ];
    for (final (foreign, network, level, expected) in cases) {
      test('fremd=$foreign Netzziel=$network Stufe ${level.name} → '
          '${expected.action.name}', () {
        final tool = network ? net : noNet;
        final p = RiskPolicy()..setLevel(tool.name, level);
        expect(p.decide(tool, 's', foreignContent: foreign), expected);
      });
    }
  });

  group('gesperrtes Gerät', () {
    for (final level in SecurityLevel.values) {
      test(
        'Netzziel nach Fremdem wartet auf Entsperren (Stufe ${level.name})',
        () {
          final p = RiskPolicy()..setLevel(net.name, level);
          expect(
            p.decide(
              net,
              's',
              access: AccessContext.lockedUnknownVoice,
              foreignContent: true,
            ),
            _unlock,
          );
        },
      );
    }
    test('ohne Fremdes bleibt Stufe A auf gesperrtem Gerät erlaubt', () {
      final p = RiskPolicy()..setLevel(net.name, SecurityLevel.a);
      expect(
        p.decide(net, 's', access: AccessContext.lockedUnknownVoice),
        _allow,
      );
    });
    test('ohne Netzziel zählt auch gesperrt nur die Stufe', () {
      final p = RiskPolicy()..setLevel(noNet.name, SecurityLevel.a);
      expect(
        p.decide(
          noNet,
          's',
          access: AccessContext.lockedUnknownVoice,
          foreignContent: true,
        ),
        _allow,
      );
    });
  });

  group('Overrides und Sitzungssperre', () {
    test('Override deny gewinnt (entsperrt und gesperrt)', () {
      final p = RiskPolicy(overrides: {net.name: PolicyAction.deny});
      for (final access in [
        AccessContext.unlocked,
        AccessContext.lockedUnknownVoice,
      ]) {
        expect(
          p.decide(net, 's', access: access, foreignContent: true).action,
          PolicyAction.deny,
        );
      }
    });
    test('Override confirm hebt ein Tool ohne Netzziel auch ohne Fremdes', () {
      final p = RiskPolicy(overrides: {noNet.name: PolicyAction.confirm});
      expect(p.decide(noNet, 's'), _confirm);
    });
    test('Sitzungssperre: external-Tool abgelehnt, read-Netztool nach '
        'Fremdem hart gesperrt (auch gesperrtes Gerät), ohne Fremdes '
        'unverändert', () {
      final p = RiskPolicy()..lockExternal('s');
      final send = FakeTool(name: 'p__send', risk: RiskLevel.external);
      expect(p.decide(send, 's').action, PolicyAction.deny);
      expect(
        p.decide(net, 's', foreignContent: true).action,
        PolicyAction.deny,
      );
      expect(
        p
            .decide(
              net,
              's',
              access: AccessContext.lockedUnknownVoice,
              foreignContent: true,
            )
            .action,
        PolicyAction.deny,
      );
      // Own texts: a web search is no „Aktion mit Außenwirkung“; the way out
      // is named (review WP157).
      expect(
        p.decide(net, 's', foreignContent: true),
        PolicyDecision.deny(RiskPolicy.networkLockedReason),
      );
      expect(p.decide(send, 's'), PolicyDecision.deny(RiskPolicy.lockedReason));
      expect(RiskPolicy.networkLockedReason, contains('Neues Thema'));
      expect(RiskPolicy.networkLockedReason, contains('neu prüfen'));
      expect(p.decide(net, 's'), _allow);
      expect(p.decide(net, 'andere', foreignContent: true), _confirm);
      expect(p.decide(noNet, 's', foreignContent: true), _allow);
      expect(p.decide(send, 'andere'), _confirm);
    });
  });
}
