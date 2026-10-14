import 'package:test/test.dart';
import 'package:wendelin_storage/testing.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

void main() {
  scopedSecretStoreContract(InMemorySecretStore.new);
  scopedSecretStoreContract(
    InMemorySecretStore.new,
    prefix: 'http_tool.',
    name: 'ScopedSecretStore (http_tool.)',
  );

  test('leeres Präfix wird abgelehnt', () {
    expect(
      () => ScopedSecretStore(InMemorySecretStore(), ''),
      throwsArgumentError,
    );
  });

  test('ein Präfix, das um ein Zeichen abweicht, findet nichts', () async {
    final inner = InMemorySecretStore({'bring.password': 'pw'});
    expect(await ScopedSecretStore(inner, 'bring.').read('password'), 'pw');
    expect(await ScopedSecretStore(inner, 'bring').read('password'), isNull);
    expect(await ScopedSecretStore(inner, 'brin.').read('password'), isNull);
  });

  test('toString verrät keine Werte', () async {
    final s = ScopedSecretStore(InMemorySecretStore(), 'p.');
    await s.write('k', 'geheim-4711');
    expect('$s', isNot(contains('geheim-4711')));
  });
}
