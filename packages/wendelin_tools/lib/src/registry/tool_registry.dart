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
/// tools it finds are unlocked for that session and offered from then on.
///
/// The registry is no [ToolCatalog] itself: the agent always gets a view
/// for the privacy level of the provider in use and its session
/// ([catalogFor]), so sensitive tools cannot leak through an unfiltered
/// catalog.
final class ToolRegistry {
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
  final Map<String, Set<String>> _unlocked = {};
  // Unlocked by [preloadForRequest]; replaced with every request.
  final Map<String, Set<String>> _preloaded = {};
  final Map<String, String?> _languages = {};
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
      for (final names in _unlocked.values) {
        names.remove(tool.name);
      }
      for (final names in _preloaded.values) {
        names.remove(tool.name);
      }
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
  ///
  /// [kind] is the failure category the UI words in the app language.
  void reportError(String id, String message, {PortErrorKind? kind}) {
    _entry(id)
      ..reportedError = message
      ..reportedKind = kind;
    _changed();
  }

  /// Clears a failure set by [reportError].
  void clearError(String id) {
    _entry(id)
      ..reportedError = null
      ..reportedKind = null;
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

  /// Names of the tools unlocked by `tools__search` in [sessionId].
  Set<String> unlockedTools(String sessionId) =>
      Set.unmodifiable({...?_unlocked[sessionId], ...?_preloaded[sessionId]});

  /// Most integrations [preloadForRequest] unlocks (small models get
  /// overloaded by more).
  static const maxPreloaded = 3;

  /// Unlocks, before the first model call, the tools of the integrations
  /// that [requestText] names by topic words (`topicWordsFor` the language of [languageTag]), at
  /// most [maxPreloaded]. Only tools the provider with [level] may see are
  /// unlocked (K10); `tools__search` stays as the fallback. Without meta
  /// mode all tools are offered anyway. Returns the integration ids.
  List<String> preloadForRequest(
    String requestText,
    PrivacyLevel level, {
    required String sessionId,
    String? languageTag,
  }) {
    final active = _active(level);
    if (active.length < metaToolThreshold) return const [];
    _languages[sessionId] = languageTag;
    final topics = topicIntegrationsIn(
      requestText,
      languageTag: languageTag,
    ).toSet();
    final ids =
        <String>[
          for (final id in {for (final e in active) e.integration.id})
            if (topics.contains(id)) id,
        ]..sort(
          (a, b) =>
              _topicRank(a, languageTag).compareTo(_topicRank(b, languageTag)),
        );
    final chosen = ids.take(maxPreloaded).toSet();
    // Replaces the previous request's preload; tools found by search stay.
    final names = {
      for (final e in active)
        if (chosen.contains(e.integration.id)) e.tool.name,
    };
    final old = _preloaded[sessionId] ?? const <String>{};
    if (old.length != names.length || !old.containsAll(names)) {
      _preloaded[sessionId] = names;
      _changed();
    }
    return chosen.toList();
  }

  static int _topicRank(String id, String? languageTag) =>
      topicWordsFor(languageTag).keys.toList().indexOf(id);

  /// Forgets the tools unlocked in [sessionId] (session ended).
  void endSession(String sessionId) {
    _languages.remove(sessionId);
    final a = _unlocked.remove(sessionId);
    final b = _preloaded.remove(sessionId);
    if (a != null || b != null) _changed();
  }

  /// Specs for a provider with privacy [level] in [sessionId]: active tools
  /// sorted by name, or – from [metaToolThreshold] on – `tools__search`
  /// followed by the tools unlocked in this session.
  List<ToolSpec> activeSpecsFor(
    PrivacyLevel level, {
    required String sessionId,
  }) => [for (final tool in _offered(level, sessionId)) tool.spec];

  /// All active tools a provider with privacy [level] may see, sorted by
  /// name, also in meta mode (before `tools__search` unlocked them). For
  /// the locked path (WP154 L2), which offers a fixed subset.
  List<Tool> activeToolsFor(PrivacyLevel level) => [
    for (final e in _active(level)) e.tool,
  ];

  /// The [ToolCatalog] for a provider with privacy [level] in [sessionId].
  ToolCatalog catalogFor(PrivacyLevel level, {required String sessionId}) =>
      _LevelCatalog(this, level, sessionId);

  /// Closes [changes].
  Future<void> dispose() => _changes.close();

  // --- internals ---

  List<Tool> _offered(PrivacyLevel level, String sessionId) {
    final active = _active(level);
    if (active.length < metaToolThreshold) {
      return [for (final e in active) e.tool];
    }
    return [
      _searchTool(active),
      for (final e in active)
        if ((_unlocked[sessionId]?.contains(e.tool.name) ?? false) ||
            (_preloaded[sessionId]?.contains(e.tool.name) ?? false))
          e.tool,
    ];
  }

  Tool? _lookup(String name, PrivacyLevel level) {
    final active = _active(level);
    if (name == ToolSearchTool.toolName) {
      return active.length >= metaToolThreshold ? _searchTool(active) : null;
    }
    // In meta mode, active tools that are not unlocked yet may still be
    // called (the model guessed or remembered the name): they are enabled by
    // the user, pass the privacy filter, and validation and policy apply as
    // usual. Refusing them would only cost an extra search round.
    for (final e in active) {
      if (e.tool.name == name) return e.tool;
    }
    return null;
  }

  ToolSearchTool _searchTool(List<CatalogEntry> active) => ToolSearchTool(
    candidates: active,
    unlock: _unlock,
    languageFor: (sessionId) => _languages[sessionId],
  );

  void _unlock(String sessionId, List<String> names) {
    _unlocked.putIfAbsent(sessionId, () => {}).addAll(names);
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
  PortErrorKind? reportedKind;

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
      errorKind: reportedKind,
      status: IntegrationInfo.deriveStatus(
        available: shown.available,
        enabled: enabled,
        hasError: error != null,
        setupComplete: setup.requiredComplete(integration.setup),
      ),
    );
  }
}

/// [ToolCatalog] of a registry for one privacy level and session.
final class _LevelCatalog implements ToolCatalog {
  _LevelCatalog(this._registry, this._level, this._sessionId);

  final ToolRegistry _registry;
  final PrivacyLevel _level;
  final String _sessionId;

  @override
  List<ToolSpec> activeSpecs() =>
      _registry.activeSpecsFor(_level, sessionId: _sessionId);

  @override
  Tool? lookup(String name) => _registry._lookup(name, _level);
}
