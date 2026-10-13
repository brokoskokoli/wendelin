import 'package:test/test.dart';
import 'package:wendelin_integrations/src/common/file_queue.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  test('genau drei Versuche bei ständigem Schreibkonflikt (N4)', () async {
    expect(FileQueue.attempts, 3);
    var calls = 0;
    await expectLater(
      FileQueue.run<void>('test:a', () async {
        calls++;
        throw const WriteConflict();
      }),
      throwsA(
        isA<PortException>().having(
          (e) => e.kind,
          'kind',
          PortErrorKind.unavailable,
        ),
      ),
    );
    expect(calls, 3);
    expect(FileQueue.pending, 0);
  });

  test('dritter Versuch darf noch gelingen', () async {
    var calls = 0;
    final r = await FileQueue.run('test:b', () async {
      if (++calls < 3) throw const WriteConflict();
      return 'ok';
    });
    expect(r, 'ok');
    expect(calls, 3);
  });

  test('andere Fehler werden nicht wiederholt', () async {
    var calls = 0;
    await expectLater(
      FileQueue.run<void>('test:c', () async {
        calls++;
        throw StateError('x');
      }),
      throwsStateError,
    );
    expect(calls, 1);
    expect(const WriteConflict().toString(), 'WriteConflict');
  });
}
