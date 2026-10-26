// WP157 review round 1, finding 6: the app and the overlay share one lock
// store; saving merges instead of the last writer winning.
import 'package:test/test.dart';
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
  late _MemStore store;
  late RiskPolicy app;
  late RiskPolicy overlay;

  setUp(() async {
    store = _MemStore();
    // Both engines started with an empty store.
    app = RiskPolicy(lockStore: store);
    overlay = RiskPolicy(lockStore: store);
    await app.ready;
    await overlay.ready;
  });

  test('Sperre der App überlebt das Speichern des Overlays', () async {
    app.lockExternal('app-s', profileId: 'tee');
    await _settle();
    overlay.lockExternal('ov-s', profileId: 'tee');
    await _settle();
    expect(store.saved.keys.toSet(), {'app-s', 'ov-s'});
    final restarted = RiskPolicy(lockStore: store);
    await restarted.ready;
    expect(restarted.isExternalLocked('app-s'), isTrue);
  });

  test('Ende im Overlay löscht nur die eigene Sperre', () async {
    app.lockExternal('app-s');
    await _settle();
    overlay.lockExternal('ov-s');
    await _settle();
    overlay.endSession('ov-s');
    await _settle();
    expect(store.saved.keys, ['app-s']);
  });

  test(
    'Neuprüfung des Profils löscht auch fremde Sperren dieses Profils',
    () async {
      app.lockExternal('app-s', profileId: 'tee');
      app.lockExternal('app-t', profileId: 'other');
      await _settle();
      overlay.lockExternal('ov-s', profileId: 'x');
      await _settle();
      overlay.unlockProfile('tee');
      await _settle();
      expect(store.saved.keys.toSet(), {'app-t', 'ov-s'});
    },
  );

  test(
    'mehr als 50 Sperren: nach dem Zusammenführen die ältesten weg',
    () async {
      for (var i = 0; i < RiskPolicy.maxLockedSessions; i++) {
        app.lockExternal('a$i');
      }
      await _settle();
      overlay.lockExternal('new');
      await _settle();
      expect(store.saved.length, RiskPolicy.maxLockedSessions);
      expect(store.saved.containsKey('new'), isTrue);
      expect(store.saved.containsKey('a0'), isFalse);
    },
  );
}
