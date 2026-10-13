import 'package:wendelin_mcp/wendelin_mcp.dart';

import 'mcp_secrets.dart';
import 'mcp_templates.dart';

/// What the „Server hinzufügen“ form produces. Secret values only live here
/// until `McpServerSource.add` writes them to the `SecretStore`.
final class McpDraft {
  /// Creates a draft.
  McpDraft({
    required this.name,
    required this.url,
    this.transport = McpTransportKind.auto,
    this.auth = McpAuthKind.none,
    this.token,
    List<(String, String)> headers = const [],
    this.clientId,
    this.confirmAll = false,
    this.sensitive = false,
  }) : headers = List.unmodifiable(headers);

  /// Display name.
  final String name;

  /// Endpoint.
  final Uri url;

  /// Transport choice.
  final McpTransportKind transport;

  /// Authentication kind.
  final McpAuthKind auth;

  /// Bearer token ([McpAuthKind.bearer]).
  final String? token;

  /// Own headers as (name, secret value) ([McpAuthKind.headers]).
  final List<(String, String)> headers;

  /// Pre-registered OAuth client id; `null` = dynamic registration.
  final String? clientId;

  /// Every tool needs confirmation.
  final bool confirmAll;

  /// Tools only go to providers of the level for sensitive integrations.
  final bool sensitive;

  /// The configuration with secret references of server [id], and the
  /// secrets to store under them.
  (McpServerConfig, Map<String, String>) toConfig(String id, String slug) {
    final secrets = <String, String>{};
    final McpAuth authConfig;
    switch (auth) {
      case McpAuthKind.none:
        authConfig = const McpNoAuth();
      case McpAuthKind.bearer:
        final ref = McpSecretRefs.bearer(id);
        if (token case final t? when t.isNotEmpty) secrets[ref] = t;
        authConfig = McpBearerAuth(ref);
      case McpAuthKind.headers:
        final refs = <String, String>{};
        for (final (i, (name, value)) in headers.indexed) {
          final ref = McpSecretRefs.header(id, i);
          refs[name] = ref;
          if (value.isNotEmpty) secrets[ref] = value;
        }
        authConfig = McpHeadersAuth(refs);
      case McpAuthKind.oauth:
        authConfig = McpOAuth(
          tokenRef: McpSecretRefs.oauthToken(id),
          clientRef: McpSecretRefs.oauthClient(id),
          clientId: (clientId?.trim().isEmpty ?? true)
              ? null
              : clientId!.trim(),
        );
    }
    return (
      McpServerConfig(
        id: id,
        name: name.trim(),
        slug: slug,
        url: url,
        transport: transport,
        auth: authConfig,
        sensitive: sensitive,
        confirmAll: confirmAll,
      ),
      secrets,
    );
  }
}

/// Failure of the OAuth login that the UI shows as a hint.
final class McpSignInException implements Exception {
  /// Creates the failure with a German [message].
  const McpSignInException(this.message);

  /// No browser is installed (AOSP without a browser).
  static const noBrowser = McpSignInException(
    'Kein Browser installiert. Für die Anmeldung wird ein Browser '
    'gebraucht, z. B. Fennec oder Firefox aus F-Droid.',
  );

  /// German text.
  final String message;

  @override
  String toString() => message;
}
