// WP157 review round 1, finding 2: an unreadable lock store only blocks what
// the lock would block (external tools, network tools after foreign
// content), not every tool, and it has a way back.
import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

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

final class _Broken implements SessionLockStore {
  final saves = <Map<String, String>>[];

  @override
  Future<Map<String, String>> load() async => throw const FormatException('x');

  @override
  Future<void> save(Map<String, String> locks) async => saves.add(locks);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  final local = _NoNet(FakeTool(name: 'notes__read'));
  final net = FakeTool(name: 'web__search');
  final sms = FakeTool(name: 'sms__send', risk: RiskLevel.external);

  Future<(RiskPolicy, _Broken)> broken() async {
    final store = _Broken();
    final p = RiskPolicy(lockStore: store);
    await p.ready;
    return (p, store);
  }

  test('lokales read-Tool läuft, auch mit fremden Inhalten', () async {
    final (p, _) = await broken();
    expect(p.decide(local, 's').action, PolicyAction.allow);
    expect(
      p.decide(local, 's', foreignContent: true).action,
      PolicyAction.allow,
    );
  });

  test('Netz-Tool ohne Fremdes läuft', () async {
    final (p, _) = await broken();
    expect(p.decide(net, 's').action, PolicyAction.allow);
  });

  test('external-Tool und Netz-Tool nach Fremdem sind gesperrt', () async {
    final (p, _) = await broken();
    expect(p.decide(sms, 's').action, PolicyAction.deny);
    final d = p.decide(net, 's', foreignContent: true);
    expect(d.action, PolicyAction.deny);
    expect(d.reason, RiskPolicy.storeUnreadableReason);
  });

  test('Erholung: das erste Sitzungsende gibt frei und schreibt neu', () async {
    final (p, store) = await broken();
    p.lockExternal('new', profileId: 'tee');
    p.endSession('old');
    await _settle();
    expect(p.decide(sms, 'other').action, PolicyAction.confirm);
    expect(p.isExternalLocked('new'), isTrue, reason: 'eigene Sperre bleibt');
    expect(store.saves.last.keys, ['new'], reason: 'kaputter Eintrag ersetzt');
  });

  test('vor der Erholung bleibt es gesperrt', () async {
    final (p, _) = await broken();
    expect(p.isExternalLocked('x'), isTrue);
  });
}
