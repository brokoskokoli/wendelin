import 'dart:async';

import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../src/user/user_integration.dart';
import '../src/user/user_integration_sync.dart';

/// [UserIntegrationSource] for tests (WP25, reused by WP27/WP28): the
/// test sets [integrations] and calls [notify]; [deletedSecrets] records
/// the cleanup calls.
final class FakeUserIntegrationSource implements UserIntegrationSource {
  /// Creates the source of [kind] with the initial [integrations].
  FakeUserIntegrationSource({
    this.kind = UserIntegrationKind.mcp,
    List<Integration> integrations = const [],
  }) : integrations = [...integrations];

  @override
  final UserIntegrationKind kind;

  /// What [load] returns.
  List<Integration> integrations;

  /// Ids whose secrets were deleted, in order.
  final List<String> deletedSecrets = [];

  /// All cleanup calls, in order.
  final List<IntegrationRemoval> removals = [];

  /// How often [load] ran.
  int loads = 0;

  final _changes = StreamController<void>.broadcast();

  /// Replaces [integrations] and tells the sync.
  void update(List<Integration> next) {
    integrations = [...next];
    notify();
  }

  /// Emits a change.
  void notify() => _changes.add(null);

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<Integration>> load() async {
    loads++;
    return List.of(integrations);
  }

  @override
  Future<void> deleteSecrets(IntegrationRemoval removal) async {
    removals.add(removal);
    if (removal.whole) deletedSecrets.add(removal.id);
  }
}

/// A user-defined integration [id] with read tools named `<id>__<tool>`.
FakeIntegration userIntegration(
  String id, {
  List<String> tools = const ['ping'],
  String? displayName,
}) => FakeIntegration(
  id: id,
  displayName: displayName ?? id,
  tools: [
    for (final t in tools) FakeTool(name: t.contains('__') ? t : '${id}__$t'),
  ],
);

/// [UserIntegrationRegistry] with the rules of the app's `ToolRegistry`
/// (same `ArgumentError` messages for clashes).
final class FakeUserIntegrationRegistry implements UserIntegrationRegistry {
  /// Reserved tool names (like `tools__search`).
  static const reservedToolNames = {'tools__search'};

  /// The registered integrations by id.
  final Map<String, Integration> integrations = {};

  /// The switch of each registered integration.
  final Map<String, bool> enabled = {};

  /// Names of all registered tools.
  Set<String> get toolNames => {
    for (final i in integrations.values)
      for (final t in i.tools) t.name,
  };

  @override
  bool isEnabled(String id) => enabled[id] ?? false;

  @override
  Future<void> register(
    Integration integration, {
    required bool enabled,
  }) async {
    final id = integration.id;
    if (integrations.containsKey(id)) {
      throw ArgumentError.value(id, 'integration.id', 'bereits registriert');
    }
    final names = <String>{};
    for (final tool in integration.tools) {
      final name = tool.name;
      if (reservedToolNames.contains(name)) {
        throw ArgumentError.value(name, 'tool.name', 'reservierter Name');
      }
      if (!names.add(name) || toolNames.contains(name)) {
        throw ArgumentError.value(name, 'tool.name', 'doppelter Tool-Name');
      }
    }
    integrations[id] = integration;
    this.enabled[id] = enabled;
  }

  @override
  void unregister(String id) {
    integrations.remove(id);
    enabled.remove(id);
  }
}

/// [UserIntegrationSwitches] in memory.
final class FakeUserIntegrationSwitches implements UserIntegrationSwitches {
  /// Creates the switches with [initial] values.
  FakeUserIntegrationSwitches([Map<String, bool> initial = const {}])
    : values = {...initial};

  /// The stored switches by integration id.
  final Map<String, bool> values;

  @override
  Future<bool?> stored(String id) async => values[id];

  @override
  Future<void> forget(String id) async => values.remove(id);
}
