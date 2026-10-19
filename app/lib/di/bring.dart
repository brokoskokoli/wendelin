import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../platform/app_share.dart';
import 'providers.dart';

/// [BringSecrets] on the app's [SecretStore]: only the cached session
/// (tokens) of the Bring! account. E-mail and password are never stored
/// (WP107); older versions' `bring.email` / `bring.password` are deleted.
/// Never settings JSON, SQLite, logs or exports.
final class SecretStoreBringSecrets implements BringSecrets {
  /// Creates the adapter and starts the cleanup of the old login keys
  /// ([removeLegacyLogin], idempotent).
  SecretStoreBringSecrets(SecretStore store)
    : store = ScopedSecretStore(store, namespace) {
    _legacy = removeLegacyLogin();
  }

  /// The Bring! part of the device secret store (keys `bring.*`).
  final ScopedSecretStore store;

  /// Prefix of all Bring! keys in the device secret store.
  static const namespace = 'bring.';

  /// Old key of the login e-mail (`bring.email`): only deleted.
  static const emailKey = 'email';

  /// Old key of the password (`bring.password`): only deleted.
  static const passwordKey = 'password';

  /// Key of the session, JSON of [BringAuth] (`bring.session` on the
  /// device).
  static const sessionKey = 'session';

  late final Future<void> _legacy;

  /// Migration: deletes the stored e-mail and password of earlier versions;
  /// the session stays. Idempotent, runs at construction and before every
  /// read of the session.
  Future<void> removeLegacyLogin() async {
    await store.delete(emailKey);
    await store.delete(passwordKey);
  }

  @override
  Future<BringAuth?> auth() async {
    await _legacy;
    final raw = await store.read(sessionKey);
    if (raw == null) return null;
    try {
      return BringAuth.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveAuth(BringAuth? auth) => auth == null
      ? store.delete(sessionKey)
      : store.write(sessionKey, jsonEncode(auth.toJson()));

  /// Deletes the session (and any old login keys).
  Future<void> clear() async {
    // Delete the keys directly: deleteAll() would read (decrypt) every
    // stored secret just to list keys.
    await removeLegacyLogin();
    await store.delete(sessionKey);
  }

  @override
  String toString() => 'SecretStoreBringSecrets(<verborgen>)';
}

/// Client of the unofficial Bring! API; tests override it with
/// `FakeBringApi`.
final bringApiProvider = Provider<BringApi>(
  (ref) => HttpBringApi(client: ref.watch(httpClientProvider)),
);

/// Where the Bring! login and session live.
final bringSecretsProvider = Provider<SecretStoreBringSecrets>(
  (ref) => SecretStoreBringSecrets(ref.watch(secretStoreProvider)),
);

/// Hands text to another app (Bring! fallback); tests override it.
final appShareProvider = Provider<ShareToApp>((ref) => shareTextToApp);

/// The built Bring! integration, if it is registered (not in the demo
/// mode).
BringIntegration? bringIntegrationOf(Map<String, Integration> integrations) =>
    switch (integrations['bring']) {
      final i? => switch (unwrapIntegration(i)) {
        final BringIntegration b => b,
        _ => null,
      },
      null => null,
    };

/// Signs in with [email] and [password]: checks them against the API and
/// stores **only the new session** (tokens); e-mail and password are not
/// kept, not even on failure. Returns `null` on success, else a German
/// message (nothing is stored then).
Future<String?> bringSignIn({
  required BringApi api,
  required SecretStoreBringSecrets secrets,
  required BringIntegration? integration,
  required String email,
  required String password,
}) async {
  final BringAuth auth;
  try {
    auth = await api.login(email, password);
  } on PortException catch (e) {
    return e.message;
  }
  await integration?.signOut();
  await secrets.saveAuth(auth);
  return null;
}

/// Signs out: forgets the session and deletes the tokens.
Future<void> bringSignOut({
  required SecretStoreBringSecrets secrets,
  required BringIntegration? integration,
}) async {
  await integration?.signOut();
  await secrets.clear();
}
