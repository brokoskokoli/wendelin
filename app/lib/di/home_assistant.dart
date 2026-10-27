import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../platform/ha_discovery.dart';
import 'providers.dart';

/// [HaSecrets] and [HaEntityStore] on the app's [SecretStore]: address and
/// token of the Home Assistant instance (`ha.url`, `ha.token`) and the
/// approved entities (`ha.entities`, JSON). Never settings JSON, SQLite,
/// logs or exports.
final class SecretStoreHa implements HaSecrets, HaEntityStore {
  /// Creates the adapter.
  SecretStoreHa(SecretStore store)
    : store = ScopedSecretStore(store, namespace);

  /// The Home Assistant part of the device secret store (keys `ha.*`).
  final ScopedSecretStore store;

  /// Prefix of all Home Assistant keys in the device secret store.
  static const namespace = 'ha.';

  /// Key of the address (`ha.url` on the device).
  static const urlKey = 'url';

  /// Key of the token (`ha.token` on the device).
  static const tokenKey = 'token';

  /// Key of the approved entities (`ha.entities` on the device).
  static const entitiesKey = 'entities';

  @override
  Future<HaEndpoint?> endpoint() async {
    final url = await store.read(urlKey);
    final token = await store.read(tokenKey);
    if (url == null || token == null) return null;
    return HaEndpoint(url: url, token: token);
  }

  @override
  Future<void> saveEndpoint(HaEndpoint? endpoint) async {
    if (endpoint == null) {
      await store.delete(urlKey);
      await store.delete(tokenKey);
      return;
    }
    await store.write(urlKey, endpoint.url);
    await store.write(tokenKey, endpoint.token);
  }

  /// The decoded entities, kept in memory so that the prompt build does not
  /// decrypt and parse them on every request; dropped by [save] and [clear]
  /// and not set when reading fails.
  List<HaEntity>? _cache;

  @override
  Future<List<HaEntity>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final loaded = List<HaEntity>.unmodifiable(await _read());
    _cache = loaded;
    return loaded;
  }

  Future<List<HaEntity>> _read() async {
    final raw = await store.read(entitiesKey);
    if (raw == null) return const [];
    try {
      final json = jsonDecode(raw);
      if (json is! List<Object?>) return const [];
      return [for (final j in json) ?HaEntity.fromJson(j)];
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> save(List<HaEntity> entities) async {
    _cache = null;
    if (entities.isEmpty) {
      await store.delete(entitiesKey);
    } else {
      await store.write(
        entitiesKey,
        jsonEncode([for (final e in entities) e.toJson()]),
      );
    }
    _cache = null;
  }

  /// Key of the time of the last comparison (`ha.synced` on the device).
  static const syncedKey = 'synced';

  @override
  Future<DateTime?> lastSync() async {
    final raw = await store.read(syncedKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  @override
  Future<void> saveLastSync(DateTime time) =>
      store.write(syncedKey, time.toUtc().toIso8601String());

  /// Key of the levels per device kind (`ha.kind_levels` on the device,
  /// WP160): JSON map `{"light":"a",...}`.
  static const kindLevelsKey = 'kind_levels';

  HaKindLevels? _kinds;

  @override
  Future<HaKindLevels> kindLevels() async {
    final cached = _kinds;
    if (cached != null) return cached;
    final raw = await store.read(kindLevelsKey);
    HaKindLevels levels;
    if (raw == null) {
      levels = const HaKindLevels();
    } else {
      try {
        levels = HaKindLevels.fromJson(jsonDecode(raw));
      } on FormatException {
        levels = const HaKindLevels.broken();
      }
    }
    return _kinds = levels;
  }

  @override
  Future<void> saveKindLevels(HaKindLevels levels) async {
    _kinds = null;
    if (levels.raw.isEmpty && !levels.isBroken) {
      await store.delete(kindLevelsKey);
    } else {
      await store.write(kindLevelsKey, jsonEncode(levels.toJson()));
    }
    _kinds = null;
  }

  /// Deletes address, token and approved entities.
  Future<void> clear() async {
    _cache = null;
    await store.delete(urlKey);
    await store.delete(tokenKey);
    await store.delete(entitiesKey);
    await store.delete(kindLevelsKey);
    _kinds = null;
    _cache = null;
    await store.delete(syncedKey);
  }

  @override
  String toString() => 'SecretStoreHa(<verborgen>)';
}

/// Address, token and approved entities of Home Assistant.
final haStoreProvider = Provider<SecretStoreHa>(
  (ref) => SecretStoreHa(ref.watch(secretStoreProvider)),
);

/// Client of the Home Assistant API; tests override it with `FakeHaApi`.
final haApiProvider = Provider<HaApi>(
  (ref) => HttpHaApi(
    ref.watch(haStoreProvider),
    client: ref.watch(httpClientProvider),
  ),
);

/// mDNS search for Home Assistant in the Wi-Fi; tests override it.
final haDiscoveryProvider = Provider<HaDiscovery>((ref) => MdnsHaDiscovery());

/// The built Home Assistant integration, if it is registered (not in the
/// demo mode).
HaIntegration? haIntegrationOf(Map<String, Integration> integrations) =>
    switch (integrations['ha']) {
      final i? => switch (unwrapIntegration(i)) {
        final HaIntegration h => h,
        _ => null,
      },
      null => null,
    };

/// Connects to Home Assistant: checks [address] ([HaUrl.parse], `http` only
/// for private hosts) and [token] against the API first, then keeps them.
/// Returns `null` on success, else a German message (nothing is kept then).
Future<String?> haConnect({
  required HaApi api,
  required SecretStoreHa store,
  required String address,
  required String token,
}) async {
  final HaEndpoint endpoint;
  try {
    endpoint = HaEndpoint(url: HaUrl.parse(address), token: token.trim());
  } on PortException catch (e) {
    return e.message;
  }
  if (endpoint.token.isEmpty) return 'Bitte das Token eingeben.';
  final previous = await store.endpoint();
  await store.saveEndpoint(endpoint);
  try {
    await api.check();
  } on PortException catch (e) {
    await store.saveEndpoint(previous);
    return e.message;
  }
  // A different instance has different entities.
  if (previous?.url != endpoint.url) {
    await store.save(const []);
    await store.store.delete(SecretStoreHa.syncedKey);
  }
  return null;
}

/// Disconnects: deletes address, token and approved entities.
Future<void> haDisconnect(SecretStoreHa store) => store.clear();
