import 'package:flutter/foundation.dart' show debugPrint;
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../voice/speaker/person_scope.dart';
import 'audit_recorder.dart';
import 'locked_scope.dart';
import 'provider_config.dart';
import 'storage_adapters.dart';

/// Builds the agent for one request (replaceable in tests).
abstract interface class AgentRunFactory {
  /// An agent for one request in [sessionId] with the targets of
  /// [providers].
  ///
  /// [person] is the recognized person's scope (WP92b): address, memory
  /// namespace. Without it the request behaves as before.
  ///
  /// [locked] (WP154 L2) is the scope of a request on a locked device: only
  /// its tools, no history, no memory unless `memory__search` is among
  /// them, nothing stored. `null` = unlocked.
  AgentRun create(
    ProviderConfig providers,
    String sessionId, {
    PersonScope person = PersonScope.standard,
    LockedScope? locked,
  });
}

/// Builds one [AgentRun] per request, wired to the registry, the local
/// database and the audit log.
final class AgentFactory implements AgentRunFactory {
  /// Creates the factory.
  const AgentFactory({
    required this.registry,
    required this.storage,
    required this.policy,
    required this.audit,
    required this.clock,
    required this.device,
    required this.costEstimator,
    required this.budgetGuard,
    this.config = const AgentConfig(),
    this.fastPath,
    this.observe,
  });

  /// Integrations and their tools.
  final ToolRegistry registry;

  /// Local database.
  final WendelinStorage storage;

  /// Risk policy of the tool executor.
  final RiskPolicy policy;

  /// Audit log (also the executor's [ToolAuditSink]).
  final AuditRecorder audit;

  /// Time source.
  final Clock clock;

  /// Locale and time zone.
  final DeviceInfo device;

  /// Prices model calls.
  final CostEstimator costEstimator;

  /// Monthly budget check.
  final BudgetGuard budgetGuard;

  /// Limits and persona.
  final AgentConfig config;

  /// Recognizes simple requests without a model (WP135 D); `null` = off.
  final FastPath? fastPath;

  /// Wraps the events of each run, typed or spoken (developer log, WP148).
  final Stream<AgentEvent> Function(Stream<AgentEvent> Function() run)? observe;

  /// An agent for one request in [sessionId] with the targets of
  /// [providers].
  ///
  /// Every model call gets the tool catalog of the current target's privacy
  /// level (`AgentRunner.catalogFor`), also after „nochmal mit …“: TEE or
  /// local targets may use sensitive tools, standard targets never see them,
  /// their calls to such tools are refused and audited, and arguments,
  /// results and the answers built from them are hidden from them. The
  /// executor looks tools up in the catalog of the level the call comes from
  /// (`ToolContext.privacyLevel`), so also `tools__search` only lists tools
  /// of that level; without a level it uses the lowest level of all targets.
  ///
  /// Memory per target: the retriever is passed if any reachable target
  /// may see the memory integration, and the runner gets the lowest level
  /// whose catalog offers `memory__search` as `memoryFloor` ([memoryFloorOf]).
  /// Weaker targets (also after „nochmal mit …“) get no memory in the
  /// system prompt; a run that sees it is tainted with that level.
  ///
  /// **Locked (WP154 L2):** [locked] narrows the run to the tools the policy
  /// allows for it. Every context source is checked: the tool specs and the
  /// prompt sections come from that catalog, the memory only if
  /// `memory__search` is allowed, the history is not read and nothing is
  /// recorded, the fast path only with `ha__call`; date, time, language and
  /// persona are no personal data of a tool. The executor decides with the
  /// same access, so a call outside the set ends as „Entsperren nötig“.
  @override
  AgentRun create(
    ProviderConfig providers,
    String sessionId, {
    PersonScope person = PersonScope.standard,
    LockedScope? locked,
  }) {
    final access = locked?.access ?? AccessContext.unlocked;
    ToolCatalog catalogFor(PrivacyLevel level) {
      final inner = registry.catalogFor(level, sessionId: sessionId);
      return locked?.narrow(inner, registry.activeToolsFor(level)) ?? inner;
    }

    final catalog = catalogFor(providers.lowestPrivacy);
    final conversation = StorageConversation(storage.conversations, sessionId);
    // Locked: the memory only enters the prompt if its search is allowed.
    final memoryAllowed =
        (locked == null || locked.tools.contains('memory__search')) &&
        _memoryAllowed(providers, catalogFor);
    final memoryFloor = memoryFloorOf(catalogFor);
    final runner = AgentRunner(
      resolver: providers.resolver(),
      contextBuilder: ContextBuilder(
        config: _configFor(person, locked),
        clock: clock,
        device: device,
        catalog: catalog,
        access: access,
        // Locked: `catalogFor` offers `memory__search` only if allowed.
        memory: memoryAllowed
            ? StorageMemoryRetriever(storage.memory, owner: person.memoryOwner)
            : null,
        // Locked: earlier turns may hold anything; none is read.
        history: locked == null ? conversation : null,
      ),
      invoker: ToolExecutor(
        catalog: catalog,
        catalogFor: catalogFor,
        policy: policy,
        audit: audit,
        access: access,
      ),
      catalogFor: catalogFor,
      onToolRefused: _recordCall(
        access,
        AuditDecision.denied,
        AuditStatus.denied,
      ),
      // The action ran, its answer was not verified and the undo failed: the
      // user must check it (WP77).
      onUndoFailed: _recordCall(
        access,
        AuditDecision.allowed,
        AuditStatus.error,
      ),
      onFixedConfirmation: _logFixed,
      fastPath: locked == null || locked.tools.contains('ha__call')
          ? fastPath
          : null,
      onFastPath: _logFast,
      fallbackTargets: providers.fallbackTargets,
      clock: clock,
      sessionId: sessionId,
      // Locked: nothing of this request is stored (K85, no history).
      recorder: locked == null ? conversation : null,
      costEstimator: costEstimator,
      budgetGuard: budgetGuard,
      memoryFloor: memoryFloor,
      memoryOwner: person.memoryOwner,
    );
    return _PreloadingRun(
      registry: registry,
      level: providers.primary.privacy,
      preload: locked == null,
      sessionId: sessionId,
      locale: device.locale,
      inner: runner,
      observe: observe,
    );
  }

  void Function(String, ToolCallBlock) _recordCall(
    AccessContext access,
    AuditDecision decision,
    AuditStatus status,
  ) =>
      (session, call) => audit.record(
        ToolAuditEntry(
          sessionId: session,
          callId: call.id,
          tool: call.name,
          argumentsJson: call.argumentsJson,
          decision: decision,
          status: status,
          duration: Duration.zero,
          whileLocked: access.locked,
        ),
      );

  /// Locked: the name is no tool data and goes to the provider; omitted.
  AgentConfig _configFor(PersonScope person, LockedScope? locked) =>
      locked != null
      ? config.withUserName(null)
      : person.address == null
      ? config
      : config.withUserName(person.address);

  static bool _memoryAllowed(
    ProviderConfig providers,
    ToolCatalog Function(PrivacyLevel) catalogFor,
  ) => [
    providers.primary,
    ...providers.others,
  ].any((t) => catalogFor(t.privacy).lookup('memory__search') != null);
}

/// WP122: logs only the tool name, never the sentence.
void _logFixed(String session, String tool) =>
    debugPrint('confirm=fixed tool=$tool');

/// WP135 D: logs only the tool name, never the request.
void _logFast(String session, String tool) => debugPrint('fastpath tool=$tool');

/// The lowest privacy level whose catalog offers `memory__search` (from
/// [catalogFor]), `tee` if none does; `null` if every level may see the
/// memory (no floor needed).
PrivacyLevel? memoryFloorOf(ToolCatalog Function(PrivacyLevel) catalogFor) {
  final weakestFirst = [...PrivacyLevel.values]
    ..sort((a, b) => a.isAtLeast(b) ? 1 : -1);
  for (final level in weakestFirst) {
    if (catalogFor(level).lookup('memory__search') != null) {
      return level == PrivacyLevel.standard ? null : level;
    }
  }
  return PrivacyLevel.tee;
}

/// Unlocks the tools of the integrations a request names (topic words)
/// before the first model call (WP119), so the model need not call
/// `tools__search` first. The privacy filter stays with the registry.
final class _PreloadingRun implements AgentRun {
  _PreloadingRun({
    required this.registry,
    required this.level,
    required this.sessionId,
    required this.locale,
    required this.inner,
    this.preload = true,
    this.observe,
  });

  final ToolRegistry registry;

  /// Locked requests unlock nothing: they offer a fixed set.
  final bool preload;
  final PrivacyLevel level;
  final String sessionId;
  final String locale;
  final AgentRun inner;
  final Stream<AgentEvent> Function(Stream<AgentEvent> Function() run)? observe;

  @override
  Stream<AgentEvent> run(UserInput input) {
    if (preload) {
      registry.preloadForRequest(
        input.text,
        level,
        sessionId: sessionId,
        languageTag: input.language ?? locale,
      );
    }
    return observe?.call(() => inner.run(input)) ?? inner.run(input);
  }

  @override
  void cancel() => inner.cancel();
}
