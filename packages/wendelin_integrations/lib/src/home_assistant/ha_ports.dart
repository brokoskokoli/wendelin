import 'ha_model.dart';

/// Home Assistant access (REST and WebSocket API).
///
/// Every method throws `PortException` only:
/// - `permissionDenied`: not set up or token rejected (HTTP 401/403),
/// - `notFound`: unknown entity (HTTP 404),
/// - `unavailable`: unreachable, timeout, 5xx,
/// - `failed`: unexpected answer (not JSON, wrong types, redirect).
///
/// Messages are German, short and never contain the token or response
/// bodies. Must pass `haApiContract`.
abstract interface class HaApi {
  /// Tests address and token (`GET /api/`); returns the version text if
  /// known, else an empty string.
  Future<String> check();

  /// All states (`GET /api/states`).
  Future<List<HaState>> states();

  /// One state (`GET /api/states/<id>`); `notFound` if unknown.
  Future<HaState> state(String entityId);

  /// Calls a service (`POST /api/services/<domain>/<service>`); [HaCall.data]
  /// contains `entity_id`.
  Future<void> callService(HaCall call);

  /// All entities with name and room (areas come from the WebSocket
  /// registries; without admin rights the rooms are empty).
  Future<List<HaEntity>> entities();
}

/// Where address and token live (app: `SecretStore`; never settings JSON,
/// SQLite, logs or exports).
abstract interface class HaSecrets {
  /// The saved endpoint, `null` if not set up.
  Future<HaEndpoint?> endpoint();

  /// Saves the endpoint; `null` deletes it.
  Future<void> saveEndpoint(HaEndpoint? endpoint);
}

/// The entities the user approved for Wendelin; only these go to the model.
abstract interface class HaEntityStore {
  /// The approved entities.
  Future<List<HaEntity>> load();

  /// Replaces the approved entities.
  Future<void> save(List<HaEntity> entities);

  /// When the approved entities were last compared with Home Assistant
  /// (WP135 A), `null` if never.
  Future<DateTime?> lastSync();

  /// Remembers the time of the last successful comparison.
  Future<void> saveLastSync(DateTime time);
}

/// Finds Home Assistant instances in the local network (mDNS
/// `_home-assistant._tcp`). Not available over Tailscale: enter the
/// address by hand there.
abstract interface class HaDiscovery {
  /// Searches for [timeout]; never throws (empty list on failure).
  Future<List<HaServer>> discover({
    Duration timeout = const Duration(seconds: 4),
  });
}
