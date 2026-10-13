import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../platform/app_share.dart';
import 'integration_decorator.dart';
import 'providers.dart';

/// [BringSecrets] on the app's [SecretStore]: e-mail and password of the
/// Bring! account and the cached session (tokens). Never settings JSON,
/// SQLite, logs or exports.
final class SecretStoreBringSecrets implements BringSecrets {
  /// Creates the adapter.
  const SecretStoreBringSecrets(this.store);

  /// The device secret store.
  final SecretStore store;

  /// Key of the login e-mail.
  static const emailKey = 'bring.email';

  /// Key of the password.
  static const passwordKey = 'bring.password';

  /// Key of the session (JSON of [BringAuth]).
  static const sessionKey = 'bring.session';

  @override
  Future<BringCredentials?> credentials() async {
    final email = await store.read(emailKey);
    final password = await store.read(passwordKey);
    if (email == null || password == null) return null;
    return BringCredentials(email: email, password: password);
  }

  @override
  Future<BringAuth?> auth() async {
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

  /// Stores the login.
  Future<void> saveCredentials(BringCredentials login) async {
    await store.write(emailKey, login.email);
    await store.write(passwordKey, login.password);
  }

  /// Deletes login and session.
  Future<void> clear() async {
    for (final key in [emailKey, passwordKey, sessionKey]) {
      await store.delete(key);
    }
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

/// Signs in with [login]: checks it against the API first, then stores it
/// together with the new session. Returns `null` on success, else a German
/// message (nothing is stored then).
Future<String?> bringSignIn({
  required BringApi api,
  required SecretStoreBringSecrets secrets,
  required BringIntegration? integration,
  required BringCredentials login,
}) async {
  final BringAuth auth;
  try {
    auth = await api.login(login.email, login.password);
  } on PortException catch (e) {
    return e.message;
  }
  await integration?.signOut();
  await secrets.saveCredentials(login);
  await secrets.saveAuth(auth);
  return null;
}

/// Signs out: forgets the session and deletes login and tokens.
Future<void> bringSignOut({
  required SecretStoreBringSecrets secrets,
  required BringIntegration? integration,
}) async {
  await integration?.signOut();
  await secrets.clear();
}
