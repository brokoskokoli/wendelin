import 'package:flutter/foundation.dart' show debugPrint;
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../voice/speaker/person_scope.dart';
import 'audit_recorder.dart';
import 'provider_config.dart';
import 'storage_adapters.dart';

/// Builds the agent for one request (replaceable in tests).
abstract interface class AgentRunFactory {
  /// An agent for one request in [sessionId] with the targets of
  /// [providers].
  ///
  /// [person] is the recognized person's scope (WP92b): address, memory
  /// namespace. Without it the request behaves as before.
  AgentRun create(
    ProviderConfig providers,
    String sessionId, {
    PersonScope person = PersonScope.standard,
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
  @override
  AgentRun create(
    ProviderConfig providers,
    String sessionId, {
    PersonScope person = PersonScope.standard,
  }) {
    final catalog = registry.catalogFor(
      providers.lowestPrivacy,
      sessionId: sessionId,
    );
    ToolCatalog catalogFor(PrivacyLevel level) =>
        registry.catalogFor(level, sessionId: sessionId);
    final conversation = StorageConversation(storage.conversations, sessionId);
    final memoryAllowed = [
      providers.primary,
      ...providers.others,
    ].any((t) => catalogFor(t.privacy).lookup('memory__search') != null);
    final memoryFloor = memoryFloorOf(catalogFor);
    final runner = AgentRunner(
      resolver: providers.resolver(),
      contextBuilder: ContextBuilder(
        config: person.address == null
            ? config
            : config.withUserName(person.address),
        clock: clock,
        device: device,
        catalog: catalog,
        memory: memoryAllowed
            ? StorageMemoryRetriever(storage.memory, owner: person.memoryOwner)
            : null,
        history: conversation,
      ),
      invoker: ToolExecutor(
        catalog: catalog,
        catalogFor: catalogFor,
        policy: policy,
        audit: audit,
      ),
      catalogFor: catalogFor,
      onToolRefused: (session, call) => audit.record(
        ToolAuditEntry(
          sessionId: session,
          callId: call.id,
          tool: call.name,
          argumentsJson: call.argumentsJson,
          decision: AuditDecision.denied,
          status: AuditStatus.denied,
          duration: Duration.zero,
        ),
      ),
      onUndoFailed: (session, call) => audit.record(
        // The action ran, its answer was not verified and the undo failed:
        // the user must check it (WP77).
        ToolAuditEntry(
          sessionId: session,
          callId: call.id,
          tool: call.name,
          argumentsJson: call.argumentsJson,
          decision: AuditDecision.allowed,
          status: AuditStatus.error,
          duration: Duration.zero,
        ),
      ),
      onFixedConfirmation: _logFixed,
      fallbackTargets: providers.fallbackTargets,
      clock: clock,
      sessionId: sessionId,
      recorder: conversation,
      costEstimator: costEstimator,
      budgetGuard: budgetGuard,
      memoryFloor: memoryFloor,
      memoryOwner: person.memoryOwner,
    );
    return _PreloadingRun(
      registry: registry,
      level: providers.primary.privacy,
      sessionId: sessionId,
      locale: device.locale,
      inner: runner,
    );
  }
}

/// WP122: logs only the tool name, never the sentence.
void _logFixed(String session, String tool) =>
    debugPrint('confirm=fixed tool=$tool');

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
  });

  final ToolRegistry registry;
  final PrivacyLevel level;
  final String sessionId;
  final String locale;
  final AgentRun inner;

  @override
  Stream<AgentEvent> run(UserInput input) {
    registry.preloadForRequest(
      input.text,
      level,
      sessionId: sessionId,
      languageTag: input.language ?? locale,
    );
    return inner.run(input);
  }

  @override
  void cancel() => inner.cancel();
}
