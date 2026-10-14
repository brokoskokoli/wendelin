import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// Namespace of the MCP secrets in the [SecretStore]; every reference of
/// `McpSecretRefs` starts with it.
const mcpSecretNamespace = 'mcp.';

/// [McpSecrets] on the app's [SecretStore] (Android Keystore): bearer
/// tokens, header values, OAuth token sets and client registrations of the
/// MCP servers. Never in the settings JSON, SQLite, logs or exports.
///
/// Passes `mcpSecretsContract` (test: `mcp_secrets_test.dart`).
final class SecretStoreMcpSecrets implements McpSecrets {
  /// Creates the adapter over [store].
  SecretStoreMcpSecrets(SecretStore store)
    : _scoped = ScopedSecretStore(store, mcpSecretNamespace);

  final ScopedSecretStore _scoped;

  // The reference `mcp.<id>.…` is the stored key itself, byte for byte.
  // Outside the namespace nothing is read or deleted; writing is refused.
  String? _key(String ref) =>
      ref.length > mcpSecretNamespace.length &&
          ref.startsWith(mcpSecretNamespace)
      ? ref.substring(mcpSecretNamespace.length)
      : null;

  @override
  Future<String?> read(String ref) async {
    final key = _key(ref);
    return key == null ? null : _scoped.read(key);
  }

  @override
  Future<void> write(String ref, String value) async {
    final key = _key(ref);
    if (key == null) {
      throw ArgumentError.value(
        ref,
        'ref',
        'außerhalb von $mcpSecretNamespace',
      );
    }
    await _scoped.write(key, value);
  }

  @override
  Future<void> delete(String ref) async {
    final key = _key(ref);
    if (key != null) await _scoped.delete(key);
  }
}
