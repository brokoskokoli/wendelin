import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Detection itself is tested in wendelin_core; here only its use by the
/// fake memory store (the memory tool is covered in memory_test.dart).
void main() {
  for (final (text, kind) in [
    ('4111 1111 1111 1111', SensitiveKind.cardNumber),
    ('Konto: DE89 3704 0044 0532 0130 00', SensitiveKind.iban),
    ('PIN: 4711', SensitiveKind.credential),
  ]) {
    test('FakeMemoryStore weist ${kind.name} mit dem Core-Grund ab', () async {
      final store = FakeMemoryStore();
      await expectLater(
        store.save(text, category: MemoryCategory.fact, source: 'test'),
        throwsA(
          isA<PortException>()
              .having((e) => e.kind, 'kind', PortErrorKind.rejected)
              .having((e) => e.message, 'message', kind.reason),
        ),
      );
      expect(store.entries, isEmpty);
    });
  }

  test('FakeMemoryStore speichert Unbedenkliches', () async {
    final store = FakeMemoryStore();
    await store.save(
      'Mag keinen Koriander',
      category: MemoryCategory.preference,
      source: 'test',
    );
    expect(store.entries, hasLength(1));
  });
}
