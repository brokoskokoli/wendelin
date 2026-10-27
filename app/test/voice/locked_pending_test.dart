// WP163 Teil B: Ablauf und Textbindung der gemerkten Anfrage bzw. des
// gemerkten Aufrufs, jede Prüfung für sich (take, takeFor).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/locked_deferred.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support/test_env.dart';

const _call = ToolCallBlock(
  id: '1',
  name: 'maps__navigate',
  argumentsJson: '{}',
);

void main() {
  late TestEnv env;
  late ProviderContainer c;

  setUp(() {
    env = TestEnv();
    c = env.container();
  });

  LockedPending pending() => c.read(lockedPendingProvider.notifier);
  LockedArmedCall armed() => c.read(lockedArmedCallProvider.notifier);

  test('ein gemerkter Aufruf wartet 60 s, der Wortlaut 30 s', () {
    expect(lockedPendingCallMaxAge, const Duration(seconds: 60));
    expect(lockedPendingMaxAge, const Duration(seconds: 30));
  });

  group('LockedPending.take', () {
    test('Aufruf: bis 60 s gültig, danach null', () {
      pending().keepCall('Navigiere', _call);
      env.clock.advance(const Duration(seconds: 60));
      expect(pending().take()?.call, _call);
      pending().keepCall('Navigiere', _call);
      env.clock.advance(const Duration(seconds: 61));
      expect(pending().take(), isNull);
    });

    test('Wortlaut: nach 31 s null', () {
      pending().keep('Wie spät ist es');
      env.clock.advance(const Duration(seconds: 31));
      expect(pending().take(), isNull);
    });

    test('zweiter Aufruf liefert null', () {
      pending().keepCall('Navigiere', _call);
      expect(pending().take(), isNotNull);
      expect(pending().take(), isNull);
    });
  });

  group('LockedArmedCall.takeFor', () {
    LockedPendingRequest request() => c.read(lockedPendingProvider)!;

    void arm() {
      pending().keepCall('Navigiere', _call);
      armed().arm(request());
    }

    test('abgelaufen: null (Alter wird hier selbst geprüft)', () {
      arm();
      env.clock.advance(const Duration(seconds: 61));
      expect(armed().takeFor('Navigiere'), isNull);
      expect(c.read(lockedArmedCallProvider), isNull, reason: 'verbraucht');
    });

    test('frisch: liefert den Aufruf', () {
      arm();
      env.clock.advance(const Duration(seconds: 59));
      expect(armed().takeFor('Navigiere'), _call);
    });

    test('anderer Text: null, Arming bleibt', () {
      arm();
      expect(armed().takeFor('Etwas anderes'), isNull);
      expect(c.read(lockedArmedCallProvider), isNotNull);
      expect(armed().takeFor('Navigiere'), _call);
    });

    test('zweiter Aufruf liefert null', () {
      arm();
      expect(armed().takeFor('Navigiere'), _call);
      expect(armed().takeFor('Navigiere'), isNull);
    });
  });
}
