import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../util/json_read.dart';

/// How a provider authenticates. Holds only *references* (`secretRef`) to
/// secrets in the `SecretStore`, never the secrets themselves.
@immutable
sealed class AuthMethod {
  const AuthMethod();

  /// Decodes an auth method written by [toJson]; throws [FormatException].
  factory AuthMethod.fromJson(Map<String, Object?> json) {
    final kind = readField<String>(json, 'kind', 'AuthMethod');
    return switch (kind) {
      ApiKeyAuth.jsonKind => ApiKeyAuth(
        readField(json, 'secretRef', 'ApiKeyAuth'),
        headerName: readOptional<String>(json, 'headerName', 'ApiKeyAuth'),
      ),
      NoAuth.jsonKind => const NoAuth(),
      CustomHeadersAuth.jsonKind => CustomHeadersAuth(
        readStringMap(json, 'secretRefs', 'CustomHeadersAuth'),
      ),
      OAuthPkceAuth.jsonKind => OAuthPkceAuth(
        clientId: readField(json, 'clientId', 'OAuthPkceAuth'),
        authorizationUrl: readField(json, 'authorizationUrl', 'OAuthPkceAuth'),
        tokenUrl: readField(json, 'tokenUrl', 'OAuthPkceAuth'),
        scopes: readStringList(json, 'scopes', 'OAuthPkceAuth'),
        tokenSecretRef: readField(json, 'tokenSecretRef', 'OAuthPkceAuth'),
      ),
      _ => throw FormatException('AuthMethod: unbekannte Art "$kind"'),
    };
  }

  /// Encodes this method as JSON (contains no secrets).
  Map<String, Object?> toJson();

  /// All secret references this method needs, for cleanup and export checks.
  Set<String> get secretRefs;
}

/// API key sent in a header (`Authorization: Bearer …` by default for
/// OpenAI-compatible providers, `x-api-key` for Anthropic).
final class ApiKeyAuth extends AuthMethod {
  /// Creates API-key auth referencing the secret [secretRef].
  const ApiKeyAuth(this.secretRef, {this.headerName});

  /// JSON discriminator.
  static const jsonKind = 'apiKey';

  /// Key of the secret in the `SecretStore`.
  final String secretRef;

  /// Header to send the key in; `null` = adapter default.
  final String? headerName;

  @override
  Set<String> get secretRefs => {secretRef};

  @override
  Map<String, Object?> toJson() => {
    'kind': jsonKind,
    'secretRef': secretRef,
    if (headerName != null) 'headerName': headerName,
  };

  @override
  bool operator ==(Object other) =>
      other is ApiKeyAuth &&
      other.secretRef == secretRef &&
      other.headerName == headerName;

  @override
  int get hashCode => Object.hash(jsonKind, secretRef, headerName);

  @override
  String toString() => 'ApiKeyAuth($secretRef)';
}

/// No authentication (local servers).
final class NoAuth extends AuthMethod {
  /// Creates no-auth.
  const NoAuth();

  /// JSON discriminator.
  static const jsonKind = 'none';

  @override
  Set<String> get secretRefs => const {};

  @override
  Map<String, Object?> toJson() => {'kind': jsonKind};

  @override
  bool operator ==(Object other) => other is NoAuth;

  @override
  int get hashCode => jsonKind.hashCode;

  @override
  String toString() => 'NoAuth()';
}

/// Arbitrary secret headers: header name → secret reference.
final class CustomHeadersAuth extends AuthMethod {
  /// Creates custom-header auth.
  CustomHeadersAuth(Map<String, String> secretRefsByHeader)
    : secretRefsByHeader = Map.unmodifiable(secretRefsByHeader);

  /// JSON discriminator.
  static const jsonKind = 'customHeaders';

  /// Header name → key of the secret in the `SecretStore`.
  final Map<String, String> secretRefsByHeader;

  @override
  Set<String> get secretRefs => secretRefsByHeader.values.toSet();

  @override
  Map<String, Object?> toJson() => {
    'kind': jsonKind,
    'secretRefs': secretRefsByHeader,
  };

  @override
  bool operator ==(Object other) =>
      other is CustomHeadersAuth &&
      const MapEquality<String, String>().equals(
        other.secretRefsByHeader,
        secretRefsByHeader,
      );

  @override
  int get hashCode => Object.hash(
    jsonKind,
    const MapEquality<String, String>().hash(secretRefsByHeader),
  );

  @override
  String toString() => 'CustomHeadersAuth(${secretRefsByHeader.keys})';
}

/// OAuth 2.0 authorization code flow with PKCE. Type only – the flow is not
/// implemented yet (concept: later module, e.g. OpenRouter).
final class OAuthPkceAuth extends AuthMethod {
  /// Creates OAuth/PKCE auth.
  OAuthPkceAuth({
    required this.clientId,
    required this.authorizationUrl,
    required this.tokenUrl,
    required this.tokenSecretRef,
    List<String> scopes = const [],
  }) : scopes = List.unmodifiable(scopes);

  /// JSON discriminator.
  static const jsonKind = 'oauthPkce';

  /// Public client id.
  final String clientId;

  /// Authorization endpoint.
  final String authorizationUrl;

  /// Token endpoint.
  final String tokenUrl;

  /// Requested scopes.
  final List<String> scopes;

  /// Key of the stored token set in the `SecretStore`.
  final String tokenSecretRef;

  @override
  Set<String> get secretRefs => {tokenSecretRef};

  @override
  Map<String, Object?> toJson() => {
    'kind': jsonKind,
    'clientId': clientId,
    'authorizationUrl': authorizationUrl,
    'tokenUrl': tokenUrl,
    'scopes': scopes,
    'tokenSecretRef': tokenSecretRef,
  };

  @override
  bool operator ==(Object other) =>
      other is OAuthPkceAuth &&
      other.clientId == clientId &&
      other.authorizationUrl == authorizationUrl &&
      other.tokenUrl == tokenUrl &&
      other.tokenSecretRef == tokenSecretRef &&
      const ListEquality<String>().equals(other.scopes, scopes);

  @override
  int get hashCode => Object.hash(
    jsonKind,
    clientId,
    authorizationUrl,
    tokenUrl,
    tokenSecretRef,
    const ListEquality<String>().hash(scopes),
  );

  @override
  String toString() => 'OAuthPkceAuth($clientId)';
}
