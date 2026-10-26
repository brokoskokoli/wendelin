// Gerätetest (WP157, ADR 0023): die Sitzungssperre nach roter Quittung
// überlebt einen Neustart, mit der echten SQLite-Datenbank der App.
//
// Nur auf dem Emulator, mit explizitem Serial:
//   tool/e2e_android.sh integration_test/session_lock_e2e_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/session_lock_store.dart';
import 'package:wendelin/main.dart' as app show openAppStorage;
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const session = 'e2e-wp157-session';

  WendelinStorage? open;

  /// Opens the app database anew (the previous handle is closed first, like
  /// after a restart) and builds a policy on it.
  Future<RiskPolicy> openPolicy() async {
    await open?.close();
    final (storage, _) = await app.openAppStorage();
    open = storage;
    final policy = RiskPolicy(
      lockStore: SettingsSessionLockStore(storage.settings),
    );
    await policy.ready;
    return policy;
  }

  tearDownAll(() => open?.close());

  test('Sperre überlebt den Neustart, endet mit Sitzung und grüner '
      'Neuprüfung', () async {
    final send = FakeTool(name: 'p__send', risk: RiskLevel.external);
    var policy = await openPolicy();
    policy.endSession(session);
    expect(policy.decide(send, session), PolicyDecision.confirm);

    policy.lockExternal(session, profileId: 'phala');
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // "Neustart": neue Policy auf derselben Datenbank.
    policy = await openPolicy();
    expect(policy.isExternalLocked(session), isTrue);
    expect(policy.decide(send, session).action, PolicyAction.deny);

    policy.unlockProfile('phala');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    policy = await openPolicy();
    expect(policy.isExternalLocked(session), isFalse);

    policy.lockExternal(session);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    policy = await openPolicy();
    expect(policy.isExternalLocked(session), isTrue);
    policy.endSession(session);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    policy = await openPolicy();
    expect(policy.isExternalLocked(session), isFalse);
  });
}
