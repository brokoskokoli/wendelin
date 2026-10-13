import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import 'app_settings.dart';

/// Kind of a user-defined integration; shown as badge in the list.
enum UserIntegrationKind {
  /// A configured MCP server (WP27).
  mcp('MCP'),

  /// Declarative HTTP tools (WP28).
  http('HTTP');

  const UserIntegrationKind(this.badge);

  /// Badge text in the integration list.
  final String badge;
}

/// A source of user-defined integrations (ADR 0012): MCP servers, HTTP
/// tools. Unlike the built-in ones (`IntegrationSpec`) their number and
/// tools change at runtime when the user adds, edits or deletes one.
///
/// [UserIntegrationSync] registers what [load] returns, follows [changes]
/// and calls [deleteSecrets] once an integration has disappeared.
abstract interface class UserIntegrationSource {
  /// What this source provides.
  UserIntegrationKind get kind;

  /// The current integrations, built from the stored configuration. An
  /// unchanged integration must be returned as the *identical* object; a
  /// new object counts as changed and is registered again (new tools,
  /// new URL, …). Ids must not clash with other integrations.
  Future<List<Integration>> load();

  /// Emits when [load] would return something else.
  Stream<void> get changes;

  /// Removes the secrets (token, header values, OAuth tokens) of the
  /// deleted integration [id] from the `SecretStore`.
  Future<void> deleteSecrets(String id);
}

/// Called with the id of a deleted user-defined integration (cleanup).
typedef IntegrationCleanup = Future<void> Function(String id);

/// Keeps the [ToolRegistry] in step with the [UserIntegrationSource]s
/// (ADR 0012):
///
/// - new integrations are registered with their stored switch
///   (`AppSettings.integrationEnabled`), so a restart restores it;
/// - a changed integration (new object) replaces the old one and keeps
///   the current switch;
/// - a removed integration is unregistered; its source deletes its
///   secrets, then [cleanups] run and the stored switch is removed;
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
    required this.settings,
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
  final ToolRegistry registry;

  /// Where the switches are stored.
  final SettingsRepository settings;

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

    for (final id in current.keys.toList()) {
      if (!next.containsKey(id)) await _remove(source, current, id);
    }
    for (final integration in next.values) {
      final old = current[integration.id];
      if (identical(old, integration)) continue;
      if (old == null) {
        final enabled =
            await settings.get(
              AppSettings.integrationEnabled(integration.id),
            ) ??
            false;
        if (await _register(source, integration, enabled: enabled)) {
          current[integration.id] = integration;
        }
      } else {
        // Changed: replace, keep the switch; if the new version is refused
        // the old one stays registered.
        final enabled = registry.info(old.id).enabled;
        registry.unregister(old.id);
        if (await _register(source, integration, enabled: enabled)) {
          current[integration.id] = integration;
        } else {
          final reason = _rejected[integration.id];
          await _register(source, old, enabled: enabled);
          // Keep the refusal of the new version visible.
          if (reason != null) _rejected[integration.id] = reason;
        }
      }
    }
  }

  Future<bool> _register(
    UserIntegrationSource source,
    Integration integration, {
    required bool enabled,
  }) async {
    try {
      await registry.registerIntegration(
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

  Future<void> _remove(
    UserIntegrationSource source,
    Map<String, Integration> current,
    String id,
  ) async {
    current.remove(id);
    registry.unregister(id);
    _rejected.remove(id);
    await _guard(() => source.deleteSecrets(id));
    for (final cleanup in cleanups) {
      await _guard(() => cleanup(id));
    }
    await _guard(() => settings.remove(AppSettings.integrationEnabled(id)));
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
