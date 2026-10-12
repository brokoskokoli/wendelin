import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/secure_secret_store.dart';
import 'package:wendelin_storage/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The plugin's in-memory test platform stands in for the Keystore.
  secretStoreContract(() {
    FlutterSecureStorage.setMockInitialValues({});
    return SecureSecretStore();
  }, name: 'SecureSecretStore');

  test('liest vorhandene Werte der Plattform', () async {
    FlutterSecureStorage.setMockInitialValues({'provider.claude': 'k-1'});
    final store = SecureSecretStore();
    expect(await store.read('provider.claude'), 'k-1');
    expect(await store.listKeys(), {'provider.claude'});
  });
}
