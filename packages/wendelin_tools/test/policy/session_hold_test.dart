// WP157 review round 1: a session that ends while a run of it is going keeps
// its lock until the run is over (finding 1).
import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

final class _MemStore implements SessionLockStore {
  Map<String, String> saved = {};

  @override
  Future<Map<String, String>> load() async => Map.of(saved);

  @override
  Future<void> save(Map<String, String> locks) async => saved = Map.of(locks);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  final sms = FakeTool(name: 'sms__send', risk: RiskLevel.external);

  test(
    'Sitzungsende bei laufendem Lauf: Sperre bleibt, Speicher auch',
    () async {
      final store = _MemStore();
      final p = RiskPolicy(lockStore: store);
      p.holdSession('s');
      p.lockExternal('s', profileId: 'tee');
      p.endSession('s');
      await _settle();
      expect(p.isExternalLocked('s'), isTrue);
      expect(p.decide(sms, 's').action, PolicyAction.deny);
      expect(store.saved.keys, ['s']);
    },
  );

  test('Ende des Laufs setzt das aufgeschobene Sitzungsende um', () async {
    final store = _MemStore();
    final p = RiskPolicy(lockStore: store);
    p.holdSession('s');
    p.lockExternal('s', profileId: 'tee');
    p.endSession('s');
    p.releaseSession('s');
    await _settle();
    expect(p.isExternalLocked('s'), isFalse);
    expect(store.saved, isEmpty);
  });

  test('zwei Läufe: erst der letzte gibt frei', () {
    final p = RiskPolicy();
    p.holdSession('s');
    p.holdSession('s');
    p.lockExternal('s');
    p.endSession('s');
    p.releaseSession('s');
    expect(p.isExternalLocked('s'), isTrue);
    p.releaseSession('s');
    expect(p.isExternalLocked('s'), isFalse);
  });

  test('ohne Lauf wirkt das Sitzungsende sofort', () {
    final p = RiskPolicy()..lockExternal('s');
    p.endSession('s');
    expect(p.isExternalLocked('s'), isFalse);
  });

  test('Freigeben ohne Sitzungsende lässt die Sperre stehen', () {
    final p = RiskPolicy()..holdSession('s');
    p.lockExternal('s');
    p.releaseSession('s');
    expect(p.isExternalLocked('s'), isTrue);
  });

  test('neue Sperre nach aufgeschobenem Ende zählt als eigene Sperre', () {
    // The run locks again after the session ended: still gone after release
    // (the conversation is over), no stale lock for a dead id.
    final p = RiskPolicy()..holdSession('s');
    p.endSession('s');
    p.lockExternal('s');
    expect(p.isExternalLocked('s'), isTrue, reason: 'während des Laufs');
    p.releaseSession('s');
    expect(p.isExternalLocked('s'), isFalse);
  });

  test('Executor reicht hold/release an die Policy weiter', () {
    final p = RiskPolicy();
    final ex = ToolExecutor(catalog: FakeToolCatalog([sms]), policy: p);
    (ex as SessionLockable).holdSession('s');
    p.lockExternal('s');
    p.endSession('s');
    expect(p.isExternalLocked('s'), isTrue);
    ex.releaseSession('s');
    expect(p.isExternalLocked('s'), isFalse);
  });
}
