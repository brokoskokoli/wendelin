import 'dart:async';

import 'package:wendelin/di/user_integrations.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';

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
