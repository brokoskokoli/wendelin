import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// [McpSecrets] on the app's [SecretStore] (Android Keystore): bearer
/// tokens, header values, OAuth token sets and client registrations of the
/// MCP servers. Never in the settings JSON, SQLite, logs or exports.
///
/// Passes `mcpSecretsContract` (test: `mcp_secrets_test.dart`).
final class SecretStoreMcpSecrets implements McpSecrets {
  /// Creates the adapter over [store].
  const SecretStoreMcpSecrets(this.store);

  /// Where the secrets live.
  final SecretStore store;

  @override
  Future<String?> read(String ref) => store.read(ref);

  @override
  Future<void> write(String ref, String value) => store.write(ref, value);

  @override
  Future<void> delete(String ref) => store.delete(ref);
}

/// Secret references of one MCP server. They contain only the server id,
/// so the configuration (and its export) never holds a secret.
abstract final class McpSecretRefs {
  /// Prefix of every reference of server [serverId].
  static String prefix(String serverId) => 'mcp.$serverId.';

  /// Bearer token.
  static String bearer(String serverId) => '${prefix(serverId)}bearer';

  /// Value of the [index]th own header.
  static String header(String serverId, int index) =>
      '${prefix(serverId)}header.$index';

  /// OAuth token set (JSON).
  static String oauthToken(String serverId) => '${prefix(serverId)}oauth.token';

  /// Dynamically registered OAuth client (JSON).
  static String oauthClient(String serverId) =>
      '${prefix(serverId)}oauth.client';
}
