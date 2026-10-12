import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import 'integration_info.dart';
import 'tool_search.dart';

/// All integrations and their tools; decides which tools the model sees.
///
/// A tool is *active* if its integration is [IntegrationStatus.active] and
/// the tool itself is not switched off ([setToolEnabled]). Tools of
/// [Integration.sensitive] integrations are only offered to providers whose
/// privacy level is at least [sensitiveMinimum] (see [catalogFor]).
///
/// With [metaToolThreshold] or more active tools the model first gets only
/// the meta tool `tools__search` (with the categories in its description);
/// tools it finds are unlocked and offered from then on.
///
/// As a [ToolCatalog] the registry itself applies no privacy filter (same as
/// `catalogFor(PrivacyLevel.local)`); hand the agent [catalogFor] with the
/// level of the provider in use.
final class ToolRegistry implements ToolCatalog {
  /// Creates an empty registry for the device [platform] (no platform
  /// check if `null`).
  ToolRegistry({
    this.platform,
    this.metaToolThreshold = 30,
    this._sensitiveMinimum,
  });

  /// Platform of this device.
  final AppPlatform? platform;

  /// From this many active tools on, only `tools__search` is offered.
  final int metaToolThreshold;

  final Map<String, _Entry> _entries = {};
  final Map<String, _Entry> _toolOwner = {};
  final Set<String> _disabledTools = {};
  final Set<String> _unlocked = {};
  String? _unlockedSession;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Emits after every change of integrations, activation, status,
  /// privacy setting or unlocked tools.
  Stream<void> get changes => _changes.stream;

  PrivacyLevel? _sensitiveMinimum;

  /// Minimum provider privacy level for tools of sensitive integrations;
  /// `null` = no restriction (the user has not set one).
  PrivacyLevel? get sensitiveMinimum => _sensitiveMinimum;

  set sensitiveMinimum(PrivacyLevel? level) {
    _sensitiveMinimum = level;
    _changed();
  }

  /// Registers [integration] and checks availability and setup.
  ///
  /// Throws [ArgumentError] (before anything is registered) if the id is
  /// taken or invalid, or a tool name is invalid, reserved or already
  /// registered.
  Future<void> registerIntegration(
    Integration integration, {
    bool enabled = false,
  }) async {
    final id = integration.id;
    if (!Tool.isValidToolName(id)) {
      throw ArgumentError.value(id, 'integration.id', 'ungültige Id');
    }
    if (_entries.containsKey(id)) {
      throw ArgumentError.value(id, 'integration.id', 'bereits registriert');
    }
    final tools = List<Tool>.of(integration.tools);
    final names = <String>{};
    for (final tool in tools) {
      final name = tool.name;
      if (!Tool.isValidToolName(name)) {
        throw ArgumentError.value(name, 'tool.name', 'ungültiger Tool-Name');
      }
      if (name == ToolSearchTool.toolName) {
        throw ArgumentError.value(name, 'tool.name', 'reservierter Name');
      }
      if (!names.add(name) || _toolOwner.containsKey(name)) {
        throw ArgumentError.value(name, 'tool.name', 'doppelter Tool-Name');
      }
    }
    final entry = _Entry(integration, tools, enabled: enabled);
    _entries[id] = entry;
    for (final tool in tools) {
      _toolOwner[tool.name] = entry;
    }
    _changed();
    await _check(entry);
  }

  /// Removes the integration [id] and its tools; no-op if unknown.
  void unregister(String id) {
    final entry = _entries.remove(id);
    if (entry == null) return;
    for (final tool in entry.tools) {
      _toolOwner.remove(tool.name);
      _disabledTools.remove(tool.name);
      _unlocked.remove(tool.name);
    }
    _changed();
  }

  /// Switches the integration [id] on or off.
  void setEnabled(String id, {required bool enabled}) {
    _entry(id).enabled = enabled;
    _changed();
  }

  /// Switches a single tool on or off (default: on).
  void setToolEnabled(String toolName, {required bool enabled}) {
    if (!_toolOwner.containsKey(toolName)) {
      throw ArgumentError.value(toolName, 'toolName', 'unbekanntes Tool');
    }
    enabled ? _disabledTools.remove(toolName) : _disabledTools.add(toolName);
    _changed();
  }

  /// Whether [toolName] is switched on.
  bool isToolEnabled(String toolName) => !_disabledTools.contains(toolName);

  /// Marks the integration [id] as failed (e.g. token expired); its tools
  /// are paused until [clearError].
  void reportError(String id, String message) {
    _entry(id).reportedError = message;
    _changed();
  }

  /// Clears a failure set by [reportError].
  void clearError(String id) {
    _entry(id).reportedError = null;
    _changed();
  }

  /// Re-checks availability and setup of [id], or of all integrations
  /// (on app start and on return to the app).
  Future<void> refresh([String? id]) async {
    final entries = id == null ? _entries.values.toList() : [_entry(id)];
    await Future.wait(entries.map(_check));
  }

  /// Snapshot of the integration [id]; throws [ArgumentError] if unknown.
  IntegrationInfo info(String id) => _entry(id).info(_platformOk);

  /// Snapshots of all integrations, sorted by id.
  List<IntegrationInfo> get integrations => [
    for (final id in _entries.keys.toList()..sort()) info(id),
  ];

  /// Status of the integration [id].
  IntegrationStatus status(String id) => info(id).status;

  /// Names of the tools unlocked by `tools__search` in the current session.
  Set<String> get unlockedTools => Set.unmodifiable(_unlocked);

  /// Forgets all unlocked tools (new session).
  void resetUnlocked() {
    _unlocked.clear();
    _unlockedSession = null;
    _changed();
  }

  /// Specs for a provider with privacy [level]: active tools sorted by name,
  /// or – from [metaToolThreshold] on – `tools__search` followed by the
  /// unlocked tools.
  List<ToolSpec> activeSpecsFor(PrivacyLevel level) => [
    for (final tool in _offered(level)) tool.spec,
  ];

  @override
  List<ToolSpec> activeSpecs() => activeSpecsFor(PrivacyLevel.local);

  @override
  Tool? lookup(String name) => _lookup(name, PrivacyLevel.local);

  /// A [ToolCatalog] view for a provider with privacy [level].
  ToolCatalog catalogFor(PrivacyLevel level) => _LevelCatalog(this, level);

  /// Closes [changes].
  Future<void> dispose() => _changes.close();

  // --- internals ---

  List<Tool> _offered(PrivacyLevel level) {
    final active = _active(level);
    if (active.length < metaToolThreshold) {
      return [for (final e in active) e.tool];
    }
    return [
      _searchTool(active),
      for (final e in active)
        if (_unlocked.contains(e.tool.name)) e.tool,
    ];
  }

  Tool? _lookup(String name, PrivacyLevel level) {
    final active = _active(level);
    if (name == ToolSearchTool.toolName) {
      return active.length >= metaToolThreshold ? _searchTool(active) : null;
    }
    // In meta mode not-yet-unlocked tools may still be called: they are
    // active and the policy applies as usual.
    for (final e in active) {
      if (e.tool.name == name) return e.tool;
    }
    return null;
  }

  ToolSearchTool _searchTool(List<CatalogEntry> active) =>
      ToolSearchTool(candidates: active, unlock: _unlock);

  void _unlock(String sessionId, List<String> names) {
    if (_unlockedSession != sessionId) {
      _unlocked.clear();
      _unlockedSession = sessionId;
    }
    _unlocked.addAll(names);
    _changed();
  }

  /// Active tools the provider with [level] may see, sorted by name.
  List<CatalogEntry> _active(PrivacyLevel level) {
    final minimum = _sensitiveMinimum;
    final out = <CatalogEntry>[
      for (final entry in _entries.values)
        if (entry.info(_platformOk).status == IntegrationStatus.active &&
            (!entry.integration.sensitive ||
                minimum == null ||
                level.isAtLeast(minimum)))
          for (final tool in entry.tools)
            if (!_disabledTools.contains(tool.name))
              (integration: entry.integration, tool: tool),
    ];
    return out..sort((a, b) => a.tool.name.compareTo(b.tool.name));
  }

  bool _platformOk(Integration i) =>
      platform == null || i.platforms.contains(platform);

  _Entry _entry(String id) =>
      _entries[id] ??
      (throw ArgumentError.value(id, 'id', 'unbekannte Integration'));

  Future<void> _check(_Entry entry) async {
    if (!_platformOk(entry.integration)) return;
    try {
      final availability = await entry.integration.checkAvailability();
      final setup = await entry.integration.setupState();
      entry
        ..availability = availability
        ..setup = setup
        ..checkError = null;
    } on Object catch (e) {
      entry
        ..availability = Availability.yes
        ..checkError = 'Prüfung fehlgeschlagen: $e';
    }
    if (identical(_entries[entry.integration.id], entry)) _changed();
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }
}

/// Mutable registry state of one integration.
final class _Entry {
  _Entry(this.integration, this.tools, {required this.enabled});

  final Integration integration;
  final List<Tool> tools;
  bool enabled;
  Availability? availability;
  SetupState setup = SetupState();
  String? checkError;
  String? reportedError;

  IntegrationInfo info(bool Function(Integration) platformOk) {
    final ok = platformOk(integration);
    final shown = !ok
        ? const Availability(
            available: false,
            reason: 'Auf diesem Gerät nicht unterstützt',
          )
        : availability ??
              const Availability(available: false, reason: 'Wird geprüft');
    final error = reportedError ?? checkError;
    return IntegrationInfo(
      integration: integration,
      enabled: enabled,
      availability: shown,
      setup: setup,
      error: error,
      status: IntegrationInfo.deriveStatus(
        available: shown.available,
        enabled: enabled,
        hasError: error != null,
        setupComplete: setup.complete,
      ),
    );
  }
}

/// [ToolCatalog] of a registry for one privacy level.
final class _LevelCatalog implements ToolCatalog {
  _LevelCatalog(this._registry, this._level);

  final ToolRegistry _registry;
  final PrivacyLevel _level;

  @override
  List<ToolSpec> activeSpecs() => _registry.activeSpecsFor(_level);

  @override
  Tool? lookup(String name) => _registry._lookup(name, _level);
}
