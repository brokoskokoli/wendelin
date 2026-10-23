import '../src/home_assistant/ha_model.dart';
import '../src/home_assistant/ha_ports.dart';

/// In-memory [HaSecrets].
final class FakeHaSecrets implements HaSecrets {
  /// Creates the store, optionally with a saved [endpoint].
  FakeHaSecrets([this.saved]);

  /// The saved endpoint.
  HaEndpoint? saved;

  @override
  Future<HaEndpoint?> endpoint() async => saved;

  @override
  Future<void> saveEndpoint(HaEndpoint? endpoint) async => saved = endpoint;
}

/// In-memory [HaEntityStore].
final class FakeHaEntityStore implements HaEntityStore {
  /// Creates the store with the approved [entities].
  FakeHaEntityStore([List<HaEntity> entities = const []])
    : entities = [...entities];

  /// The approved entities.
  List<HaEntity> entities;

  /// Time of the last comparison with Home Assistant.
  DateTime? synced;

  /// Number of [save] calls.
  int saves = 0;

  @override
  Future<List<HaEntity>> load() async => [...entities];

  @override
  Future<void> save(List<HaEntity> entities) async {
    saves++;
    this.entities = [...entities];
  }

  @override
  Future<DateTime?> lastSync() async => synced;

  @override
  Future<void> saveLastSync(DateTime time) async => synced = time;
}

/// [HaDiscovery] with a fixed answer.
final class FakeHaDiscovery implements HaDiscovery {
  /// Creates the discovery; [servers] is what it "finds".
  FakeHaDiscovery([this.servers = const []]);

  /// Found instances.
  List<HaServer> servers;

  @override
  Future<List<HaServer>> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async => servers;
}
