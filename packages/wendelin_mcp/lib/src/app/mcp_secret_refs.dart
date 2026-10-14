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
