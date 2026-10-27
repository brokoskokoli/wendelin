import 'dart:async';

import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// What the tool runtime does with a call.
enum PolicyAction {
  /// Execute without asking.
  allow,

  /// Ask the user first.
  confirm,

  /// Do not execute.
  deny;

  /// The stricter of this and [other] (`allow` < `confirm` < `deny`).
  PolicyAction atLeast(PolicyAction other) =>
      index >= other.index ? this : other;
}

/// Outcome of [RiskPolicy.decide].
@immutable
final class PolicyDecision {
  const PolicyDecision._(this.action, [this.reason, this.needsUnlock = false]);

  /// Execute without asking.
  static const allow = PolicyDecision._(PolicyAction.allow);

  /// Ask the user first.
  static const confirm = PolicyDecision._(PolicyAction.confirm);

  /// Do not execute; [reason] is a German text for the model.
  factory PolicyDecision.deny(String reason) =>
      PolicyDecision._(PolicyAction.deny, reason);

  /// Do not execute: the device has to be unlocked first (WP154 L2). The
  /// text for the model is [RiskPolicy.unlockReason].
  static const unlock = PolicyDecision._(
    PolicyAction.deny,
    RiskPolicy.unlockReason,
    true,
  );

  /// The decided action.
  final PolicyAction action;

  /// Whether the call only waits for the unlock ([unlock]).
  final bool needsUnlock;

  /// Why the call is denied (only for [PolicyAction.deny]).
  final String? reason;

  @override
  bool operator ==(Object other) =>
      other is PolicyDecision &&
      other.action == action &&
      other.reason == reason &&
      other.needsUnlock == needsUnlock;

  @override
  int get hashCode => Object.hash(action, reason, needsUnlock);

  @override
  String toString() =>
      'PolicyDecision(${action.name}${reason == null ? '' : ': $reason'})';
}

/// Decides per call whether a tool runs freely, needs confirmation or is
/// denied.
///
/// Defaults per [RiskLevel]: `read` and `write` run freely (level C, write
/// tools offer undo), `external` is confirmed (level D). The user may choose
/// a [SecurityLevel] per tool (WP154, ADR 0022, [setLevel]); the policy
/// table [levelAccess] then decides, so a level can loosen as well as
/// tighten the default. Overrides ([setOverride], e.g. a disabled tool)
/// can only tighten. After [lockExternal] every `external` tool of that
/// session is denied, whatever the level; the lock is kept in the optional
/// [SessionLockStore] and so survives an engine rebuild and an app restart
/// (WP157, ADR 0023). After foreign content ([decide] `foreignContent`) a
/// tool with a network target is confirmed at least, also at level A.
final class RiskPolicy {
  /// Creates a policy with optional per-tool [overrides]; the locks of
  /// earlier runs come from [lockStore].
  RiskPolicy({
    Map<String, PolicyAction> overrides = const {},
    SessionLockStore? lockStore,
  }) : _overrides = Map.of(overrides),
       _store = lockStore {
    ready = lockStore == null ? Future.value() : _restore(lockStore);
  }

  /// Most locked conversations that are remembered (oldest are dropped; a
  /// conversation ends after minutes of inactivity anyway).
  static const maxLockedSessions = 50;

  /// Completes when the stored locks are loaded. The executor waits for it
  /// before it decides a call.
  late final Future<void> ready;

  final Map<String, PolicyAction> _overrides;
  final Map<String, SecurityLevel> _levels = {};
  final SessionLockStore? _store;
  // Session id -> profile whose answer failed ('' = unknown), oldest first.
  final Map<String, String> _locked = {};
  // The stored locks were unreadable: fail-closed, every conversation counts
  // as locked until the first conversation ends ([endSession]).
  bool _storeUnreadable = false;
  // Runs going on per session ([holdSession]) and sessions whose end waits
  // for them.
  final Map<String, int> _holds = {};
  final Set<String> _endPending = {};
  Future<void> _saving = Future.value();
  // Changes not yet written: the app and the overlay share the store, so a
  // save merges these into what is stored instead of replacing it.
  final Map<String, String> _added = {};
  final Set<String> _removed = {};
  final Set<String> _removedProfiles = {};

  /// Default security level for a risk level (the recommendation).
  static SecurityLevel defaultLevelFor(RiskLevel risk) => switch (risk) {
    RiskLevel.read || RiskLevel.write => SecurityLevel.c,
    RiskLevel.external => SecurityLevel.d,
  };

  /// The level the user stored for [tool] that counts: none for a tool with
  /// a fixed level ([LevelFixedTool]: MCP "confirm all", `ha__call_secure`).
  SecurityLevel? _storedLevel(Tool tool) {
    if (tool is LevelFixedTool && (tool as LevelFixedTool).levelFixed) {
      return null;
    }
    return _levels[tool.name];
  }

  /// The standard level of [tool]: its own ([DefaultLevelTool]) or the one
  /// of its risk ([defaultLevelFor]).
  static SecurityLevel defaultLevelOf(Tool tool) => tool is DefaultLevelTool
      ? (tool as DefaultLevelTool).defaultLevel
      : defaultLevelFor(tool.risk);

  /// Default action for a risk level.
  static PolicyAction defaultFor(RiskLevel risk) => switch (risk) {
    RiskLevel.read || RiskLevel.write => PolicyAction.allow,
    RiskLevel.external => PolicyAction.confirm,
  };

  /// The risk level a call is *treated* as: a call the policy wants
  /// confirmed counts as `external` (also a `read`/`write` tool the user made
  /// stricter), otherwise the tool's own [risk]. Shown on the confirmation
  /// card instead of `Tool.risk`.
  static RiskLevel effectiveRisk(RiskLevel risk, PolicyAction action) =>
      action == PolicyAction.confirm ? RiskLevel.external : risk;

  /// Text given to the model when external tools are locked.
  static const lockedReason =
      'Aktionen mit Außenwirkung sind in dieser Sitzung gesperrt, weil die '
      'Antwort des Anbieters nicht verifiziert werden konnte.';

  /// Text given to the model when a tool with a network target is refused
  /// after foreign content in a locked conversation (ADR 0023).
  static const networkLockedReason =
      'Netzzugriffe sind in dieser Unterhaltung gesperrt: Die Antwort des '
      'Anbieters konnte nicht verifiziert werden und es liegen fremde '
      'Inhalte vor. Sag dem Nutzer in seiner Sprache kurz, dass er ein '
      '„Neues Thema“ beginnen oder den Anbieter neu prüfen kann.';

  /// Text given to the model when the stored session locks cannot be read:
  /// external tools and network tools after foreign content stay refused.
  static const storeUnreadableReason =
      'Der Speicher der Sitzungssperren ist nicht lesbar, deshalb sind '
      'Aktionen mit Außenwirkung und Netzzugriffe nach fremden Inhalten '
      'vorsichtshalber gesperrt. Sag dem Nutzer in seiner Sprache kurz, dass '
      'ein „Neues Thema“ das behebt.';

  /// Text given to the model when the call needs the unlocked device
  /// (WP154 L2). The result summary is „Entsperren nötig“.
  static const unlockReason =
      'Entsperren nötig: Das ist bei gesperrtem Gerät nicht erlaubt. Nenne '
      'dem Nutzer kurz, was schon erledigt ist (falls etwas lief), und sag, '
      'dass er das Telefon für den Rest entsperren soll.';

  /// Text given to the model when the user disabled a tool by override.
  static const deniedReason = 'Dieses Tool ist vom Nutzer gesperrt.';

  /// Sets the override for [toolName]; it can only tighten the result of
  /// the default or the chosen level.
  void setOverride(String toolName, PolicyAction action) =>
      _overrides[toolName] = action;

  /// Removes the override for [toolName].
  void clearOverride(String toolName) => _overrides.remove(toolName);

  /// Sets the security level the user chose for [toolName].
  void setLevel(String toolName, SecurityLevel level) =>
      _levels[toolName] = level;

  /// Removes the chosen level of [toolName] (back to the default).
  void clearLevel(String toolName) => _levels.remove(toolName);

  /// The chosen level of [toolName], if any.
  SecurityLevel? levelFor(String toolName) => _levels[toolName];

  /// The configured override for [toolName], if any.
  PolicyAction? overrideFor(String toolName) => _overrides[toolName];

  Future<void> _restore(SessionLockStore store) async {
    try {
      final stored = await store.load();
      for (final e in stored.entries) {
        _locked.putIfAbsent(e.key, () => e.value);
      }
    } on Object {
      _storeUnreadable = true;
    }
  }

  /// Denies every `external` tool for [sessionId] from now on (after a red
  /// TEE receipt or a changed provider key). The lock lasts until the
  /// conversation ends ([endSession]) or the provider [profileId] was
  /// checked green again ([unlockProfile]); it is stored and survives an
  /// engine rebuild and an app restart.
  void lockExternal(String sessionId, {String? profileId}) {
    _locked.remove(sessionId); // newest last
    _locked[sessionId] = profileId ?? '';
    _added.remove(sessionId); // newest last
    _added[sessionId] = profileId ?? '';
    _removed.remove(sessionId);
    while (_locked.length > maxLockedSessions) {
      _locked.remove(_locked.keys.first);
    }
    _persist();
  }

  /// Whether [lockExternal] was called for [sessionId] (or the stored locks
  /// could not be read).
  bool isExternalLocked(String sessionId) =>
      _storeUnreadable || _locked.containsKey(sessionId);

  /// A run of [sessionId] starts. While a run is held, the end of its
  /// conversation ([endSession]) does not lift the lock: the run goes on in
  /// the background when the window leaves the screen, and its next round
  /// must not find the conversation unlocked. Counted.
  void holdSession(String sessionId) =>
      _holds[sessionId] = (_holds[sessionId] ?? 0) + 1;

  /// The run that called [holdSession] is over; a postponed
  /// [endSession] now takes effect.
  void releaseSession(String sessionId) {
    final n = (_holds[sessionId] ?? 0) - 1;
    if (n > 0) {
      _holds[sessionId] = n;
      return;
    }
    _holds.remove(sessionId);
    if (_endPending.remove(sessionId)) _applyEnd(sessionId);
  }

  /// The conversation [sessionId] ended: its lock is gone (after its last
  /// running run, [holdSession]). The first end after an unreadable store
  /// also ends that state: from then on only the locks set since count, and
  /// the broken entry is overwritten.
  void endSession(String sessionId) {
    if (_holds.containsKey(sessionId)) {
      _endPending.add(sessionId);
      return;
    }
    _applyEnd(sessionId);
  }

  void _applyEnd(String sessionId) {
    final had = _locked.remove(sessionId) != null;
    _added.remove(sessionId);
    _removed.add(sessionId);
    if (_storeUnreadable) {
      _storeUnreadable = false;
      _persist();
    } else if (had) {
      _persist();
    }
  }

  /// The provider [profileId] was checked green again („neu prüfen“): the
  /// locks its answers caused are lifted.
  void unlockProfile(String profileId) {
    _locked.removeWhere((_, p) => p == profileId);
    _added.removeWhere((_, p) => p == profileId);
    _removedProfiles.add(profileId);
    // Also without a lock of our own: the other engine may have stored one.
    _persist();
  }

  void _persist() {
    final store = _store;
    if (store == null) return;
    final snapshot = Map<String, String>.of(_locked);
    final added = Map<String, String>.of(_added);
    final removed = Set<String>.of(_removed);
    final profiles = Set<String>.of(_removedProfiles);
    _added.clear();
    _removed.clear();
    _removedProfiles.clear();
    // The lock in memory counts either way; a failing write only loses it
    // for the next start.
    _saving = _saving
        .then((_) => _merge(store, snapshot, added, removed, profiles))
        .catchError((_) {});
  }

  // Writes our changes on top of what is stored now (the other engine may
  // have locked or ended sessions since we loaded). An unreadable store is
  // overwritten with everything we know.
  Future<void> _merge(
    SessionLockStore store,
    Map<String, String> snapshot,
    Map<String, String> added,
    Set<String> removed,
    Set<String> profiles,
  ) async {
    Map<String, String> base;
    try {
      base = Map.of(await store.load());
      base.removeWhere((id, p) => removed.contains(id) || profiles.contains(p));
      for (final e in added.entries) {
        base.remove(e.key);
        base[e.key] = e.value;
      }
    } on Object {
      base = snapshot;
    }
    while (base.length > maxLockedSessions) {
      base.remove(base.keys.first);
    }
    await store.save(base);
  }

  /// The decision for running [tool] in [sessionId] in the context
  /// [access] (default: unlocked).
  ///
  /// While locked ([AccessContext.locked]) the table [levelAccess] decides
  /// alone: allowed runs, everything else (also a call that would only be
  /// confirmed unlocked) waits for the unlock, because nobody can answer a
  /// card on a locked device. The reservations stay: a tool the user
  /// disabled and the session lock of `external` tools deny as before, and a
  /// confirm-only override means "unlock". A tool that decides per device
  /// ([LevelPerDeviceTool]) is let through here; it refuses itself unless a stored level of the tool is stricter.
  ///
  /// After foreign content ([foreignContent]) a tool with a network target
  /// (no [NoNetworkTarget]) is asked about in any case: the level only adds
  /// to this minimum, level A does not lift it (the stricter wins), and a
  /// locked device waits for the unlock like level D. In a conversation with
  /// a session lock such a call is denied outright, not asked.
  PolicyDecision decide(
    Tool tool,
    String sessionId, {
    AccessContext access = AccessContext.unlocked,
    bool foreignContent = false,
  }) {
    if (tool.risk == RiskLevel.external && isExternalLocked(sessionId)) {
      return PolicyDecision.deny(
        _storeUnreadable && !_locked.containsKey(sessionId)
            ? storeUnreadableReason
            : lockedReason,
      );
    }
    final mustAsk = foreignContent && tool is! NoNetworkTarget;
    // Locked conversation + foreign content: a network tool is denied for
    // good, also after a later green receipt (the stricter wins).
    if (mustAsk && isExternalLocked(sessionId)) {
      return PolicyDecision.deny(
        _storeUnreadable && !_locked.containsKey(sessionId)
            ? storeUnreadableReason
            : networkLockedReason,
      );
    }
    final override = _overrides[tool.name];
    if (access.locked) {
      if (override == PolicyAction.deny) {
        return PolicyDecision.deny(deniedReason);
      }
      if (override == PolicyAction.confirm || mustAsk) {
        return PolicyDecision.unlock;
      }
      final stored = _storedLevel(tool);
      // A per-device tool is let through (it refuses itself), but a stored
      // tool level (the legacy "always confirm" = D) still counts: locked is
      // never looser than unlocked, the stricter of both wins.
      if (tool is LevelPerDeviceTool &&
          stored == null &&
          tool.risk != RiskLevel.external) {
        return PolicyDecision.allow;
      }
      final level = stored ?? defaultLevelOf(tool);
      return access.of(level) == LevelAccess.allowed
          ? PolicyDecision.allow
          : PolicyDecision.unlock;
    }
    final level = _storedLevel(tool);
    final base = level == null
        ? defaultFor(tool.risk)
        : switch (access.of(level)) {
            LevelAccess.allowed => PolicyAction.allow,
            LevelAccess.confirm || LevelAccess.unlock => PolicyAction.confirm,
          };
    final asked = mustAsk ? base.atLeast(PolicyAction.confirm) : base;
    final action = override == null ? asked : asked.atLeast(override);
    return switch (action) {
      PolicyAction.allow => PolicyDecision.allow,
      PolicyAction.confirm => PolicyDecision.confirm,
      PolicyAction.deny => PolicyDecision.deny(deniedReason),
    };
  }
}

/// Where the locks of conversations are kept between starts (WP157): session
/// id -> id of the provider profile whose answer failed (`''` = unknown).
abstract interface class SessionLockStore {
  /// The stored locks; throws if they cannot be read (then nothing
  /// `external` runs, fail-closed).
  Future<Map<String, String>> load();

  /// Replaces the stored locks with [locks].
  Future<void> save(Map<String, String> locks);
}
