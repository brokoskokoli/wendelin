import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import 'user_integration.dart';

/// The registry [UserIntegrationSync] registers into; the app implements
/// it on its `ToolRegistry`.
abstract interface class UserIntegrationRegistry {
  /// Whether the registered integration [id] is switched on.
  bool isEnabled(String id);

  /// Registers [integration]. Throws [ArgumentError] (nothing registered)
  /// with the message `bereits registriert` (id taken), `doppelter
  /// Tool-Name` or `reservierter Name`, and the offending value as
  /// `invalidValue`.
  Future<void> register(Integration integration, {required bool enabled});

  /// Removes the integration [id] and its tools; no-op if unknown.
  void unregister(String id);
}

/// The stored on/off switch of each user-defined integration (survives a
/// restart); the app keeps it in its settings.
abstract interface class UserIntegrationSwitches {
  /// The stored switch of [id], or `null` if never set.
  Future<bool?> stored(String id);

  /// Removes the stored switch of [id].
  Future<void> forget(String id);
}

/// Keeps the [UserIntegrationRegistry] (the app's `ToolRegistry`) in step
/// with the [UserIntegrationSource]s
/// (ADR 0012):
///
/// - new integrations are registered with their stored switch
///   ([UserIntegrationSwitches]), so a restart restores it;
/// - a changed integration (new object) replaces the old one and keeps
///   the current switch; for tools that are gone the source deletes
///   their secrets and [cleanups] run;
/// - a removed integration is unregistered; its source deletes its
///   secrets, then [cleanups] run and the stored switch is removed;
/// - tools that moved between integrations of one source keep their
///   settings and secrets;
/// - an integration whose id or tool names clash with a registered one is
///   rejected ([rejected]) instead of replacing anything.
///
/// Sources are processed one after another, so overlapping changes
/// cannot interleave.
final class UserIntegrationSync {
  /// Starts following [sources].
  UserIntegrationSync({
    required this.registry,
    required List<UserIntegrationSource> sources,
    required this.switches,
    this.cleanups = const [],
    this.decorate,
    this.onRegistered,
    this.onError,
  }) : _sources = List.unmodifiable(sources) {
    for (final source in _sources) {
      _subscriptions.add(source.changes.listen((_) => _enqueue(source)));
      _enqueue(source);
    }
    ready = _queue;
  }

  /// The registry the integrations go into.
  final UserIntegrationRegistry registry;

  /// Where the switches are stored.
  final UserIntegrationSwitches switches;

  /// Run with the id of every deleted integration, after its source
  /// deleted the secrets.
  final List<IntegrationCleanup> cleanups;

  /// Wraps an integration before it is registered (e.g. the user's
  /// „sensibel“ mark); the source's object stays the key for changes.
  final Integration Function(Integration integration)? decorate;

  /// Called after an integration was (re-)registered, e.g. to apply the
  /// user's tool switches to its new tools.
  final void Function(Integration integration)? onRegistered;

  /// Gets failures of loading a source or of a cleanup; without it they
  /// propagate to the zone.
  final void Function(Object error, StackTrace stack)? onError;

  final List<UserIntegrationSource> _sources;
  final List<StreamSubscription<void>> _subscriptions = [];
  final Map<UserIntegrationSource, Map<String, Integration>> _registered = {};
  final Map<String, (UserIntegrationSource, String)> _rejected = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Future<void> _queue = Future.value();
  bool _disposed = false;

  /// Completes once every source was loaded for the first time.
  late final Future<void> ready;

  /// Emits after every sync step (registered, removed, rejected).
  Stream<void> get changes => _changes.stream;

  /// Kind of the user-defined integration [id]; `null` for built-in ones.
  UserIntegrationKind? kindOf(String id) {
    for (final MapEntry(key: source, value: integrations)
        in _registered.entries) {
      if (integrations.containsKey(id)) return source.kind;
    }
    return null;
  }

  /// Ids of the registered user-defined integrations, in source order.
  List<String> get ids => [
    for (final integrations in _registered.values) ...integrations.keys,
  ];

  /// Integrations that were refused (id → German reason).
  Map<String, String> get rejected => {
    for (final MapEntry(key: id, value: (_, reason)) in _rejected.entries)
      id: reason,
  };

  /// Waits until all changes reported so far are processed (including
  /// change events that are still being delivered).
  Future<void> settled() async {
    // Change events of broadcast streams arrive in a microtask.
    await Future<void>.value();
    Future<void> queue;
    do {
      queue = _queue;
      await queue;
    } while (!identical(queue, _queue));
  }

  /// Stops following the sources. Registered integrations stay in the
  /// registry (it is disposed together with this sync).
  Future<void> dispose() async {
    _disposed = true;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _changes.close();
  }

  void _enqueue(UserIntegrationSource source) {
    _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await _sync(source);
      } on Object catch (e, st) {
        _report(e, st);
      }
      if (!_changes.isClosed) _changes.add(null);
    });
  }

  Future<void> _sync(UserIntegrationSource source) async {
    final loaded = await source.load();
    if (_disposed) return;
    final current = _registered.putIfAbsent(source, () => {});
    final next = {for (final i in loaded) i.id: i};
    // Refusals of integrations the source no longer has are void.
    _rejected.removeWhere(
      (id, entry) => identical(entry.$1, source) && !next.containsKey(id),
    );

    // 1. Take out everything removed or changed first, so tools may move
    //    between integrations of this source without a clash.
    final removed = <Integration>[];
    final changed = <(Integration old, Integration next, bool enabled)>[];
    for (final MapEntry(key: id, value: old) in current.entries.toList()) {
      final now = next[id];
      if (identical(now, old)) continue;
      if (now == null) {
        removed.add(old);
      } else {
        changed.add((old, now, registry.isEnabled(id)));
      }
      current.remove(id);
      registry.unregister(id);
    }

    // 2. Register new and changed versions. A refused change keeps the
    //    old version.
    final replaced = <Integration>[];
    for (final integration in next.values) {
      if (current.containsKey(integration.id)) continue;
      final change = changed
          .where((c) => c.$1.id == integration.id)
          .firstOrNull;
      final enabled =
          change?.$3 ?? await switches.stored(integration.id) ?? false;
      if (await _register(source, integration, enabled: enabled)) {
        current[integration.id] = integration;
        if (change != null) replaced.add(change.$1);
      } else if (change != null) {
        final reason = _rejected[integration.id];
        if (await _register(source, change.$1, enabled: enabled)) {
          current[integration.id] = change.$1;
        }
        // Keep the refusal of the new version visible.
        if (reason != null) _rejected[integration.id] = reason;
      }
    }

    // 3. Clean up what is really gone.
    final stillThere = {
      for (final i in current.values)
        for (final t in i.tools) t.name,
    };
    Set<String> gone(Integration old) => {
      for (final t in old.tools)
        if (!stillThere.contains(t.name)) t.name,
    };
    for (final old in removed) {
      _rejected.remove(old.id);
      await _cleanUp(
        source,
        IntegrationRemoval(integration: old, toolNames: gone(old), whole: true),
      );
      await _guard(() => switches.forget(old.id));
    }
    for (final old in replaced) {
      final tools = gone(old);
      if (tools.isEmpty) continue;
      await _cleanUp(
        source,
        IntegrationRemoval(integration: old, toolNames: tools, whole: false),
      );
    }
  }

  Future<void> _cleanUp(
    UserIntegrationSource source,
    IntegrationRemoval removal,
  ) async {
    await _guard(() => source.deleteSecrets(removal));
    for (final cleanup in cleanups) {
      await _guard(() => cleanup(removal));
    }
  }

  Future<bool> _register(
    UserIntegrationSource source,
    Integration integration, {
    required bool enabled,
  }) async {
    try {
      await registry.register(
        decorate?.call(integration) ?? integration,
        enabled: enabled,
      );
    } on ArgumentError catch (e) {
      _rejected[integration.id] = (source, _reason(e));
      return false;
    }
    _rejected.remove(integration.id);
    onRegistered?.call(integration);
    return true;
  }

  /// Runs one cleanup step; a failure is reported and the others still run.
  Future<void> _guard(Future<void> Function() step) async {
    try {
      await step();
    } on Object catch (e, st) {
      _report(e, st);
    }
  }

  void _report(Object error, StackTrace stack) {
    final handler = onError;
    if (handler == null) {
      Zone.current.handleUncaughtError(error, stack);
    } else {
      handler(error, stack);
    }
  }

  static String _reason(ArgumentError e) => switch (e.message) {
    'bereits registriert' => 'Id „${e.invalidValue}“ ist schon vergeben',
    'doppelter Tool-Name' => 'Tool-Name „${e.invalidValue}“ ist schon vergeben',
    'reservierter Name' => 'Tool-Name „${e.invalidValue}“ ist reserviert',
    _ => 'Ungültig: ${e.invalidValue}',
  };
}
