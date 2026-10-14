import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/mcp/mcp_secrets.dart';
import 'package:wendelin/platform/secure_secret_store.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_storage/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  mcpSecretsContract(
    () => SecretStoreMcpSecrets(InMemorySecretStore()),
    name: 'SecretStoreMcpSecrets (InMemorySecretStore)',
  );

  // The plugin's in-memory test platform stands in for the Keystore.
  mcpSecretsContract(() {
    FlutterSecureStorage.setMockInitialValues({});
    return SecretStoreMcpSecrets(SecureSecretStore());
  }, name: 'SecretStoreMcpSecrets (SecureSecretStore)');

  test('Referenzen enthalten nur die Server-Id', () {
    expect(McpSecretRefs.bearer('s1'), 'mcp.s1.bearer');
    expect(McpSecretRefs.header('s1', 2), 'mcp.s1.header.2');
    expect(McpSecretRefs.oauthToken('s1'), 'mcp.s1.oauth.token');
    expect(McpSecretRefs.oauthClient('s1'), 'mcp.s1.oauth.client');
    expect(McpSecretRefs.bearer('s1'), startsWith(McpSecretRefs.prefix('s1')));
  });
}
