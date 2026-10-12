import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  test('new token is not cancelled and does not throw', () {
    final t = CancelToken();
    expect(t.isCancelled, isFalse);
    expect(t.throwIfCancelled, returnsNormally);
  });

  test(
    'cancel sets flag, completes whenCancelled, throwIfCancelled throws',
    () async {
      final t = CancelToken();
      var completed = false;
      t.whenCancelled.then((_) => completed = true).ignore();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      t.cancel();
      expect(t.isCancelled, isTrue);
      await t.whenCancelled;
      expect(completed, isTrue);
      expect(t.throwIfCancelled, throwsA(isA<CancelledException>()));
    },
  );

  test('cancel is idempotent', () async {
    final t = CancelToken()
      ..cancel()
      ..cancel();
    expect(t.isCancelled, isTrue);
    await expectLater(t.whenCancelled, completes);
  });
}
