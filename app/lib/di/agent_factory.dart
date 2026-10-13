import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import 'audit_recorder.dart';
import 'provider_config.dart';
import 'storage_adapters.dart';

/// Builds the agent for one request (replaceable in tests).
abstract interface class AgentRunFactory {
  /// An agent for one request in [sessionId] with the targets of
  /// [providers].
  AgentRun create(ProviderConfig providers, String sessionId);
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
  /// level (`AgentRunner.catalogFor`), also after an escalation: TEE or
  /// local targets may use sensitive tools, standard targets never see them
  /// and their calls to such tools are refused. The executor looks tools up
  /// in the catalog of the highest level ([ProviderConfig.highestPrivacy]).
  ///
  /// Memory entries go into the system prompt, which every target of the
  /// chain may receive, so only if the catalog of the lowest level
  /// ([ProviderConfig.lowestPrivacy]) offers the memory integration.
  @override
  AgentRun create(ProviderConfig providers, String sessionId) {
    final catalog = registry.catalogFor(
      providers.lowestPrivacy,
      sessionId: sessionId,
    );
    final executorCatalog = registry.catalogFor(
      providers.highestPrivacy,
      sessionId: sessionId,
    );
    final conversation = StorageConversation(storage.conversations, sessionId);
    final memoryAllowed = catalog.lookup('memory__search') != null;
    return AgentRunner(
      resolver: providers.resolver(),
      contextBuilder: ContextBuilder(
        config: config,
        clock: clock,
        device: device,
        catalog: catalog,
        memory: memoryAllowed ? StorageMemoryRetriever(storage.memory) : null,
        history: conversation,
      ),
      invoker: ToolExecutor(
        catalog: executorCatalog,
        policy: policy,
        audit: audit,
      ),
      catalogFor: (level) => registry.catalogFor(level, sessionId: sessionId),
      clock: clock,
      sessionId: sessionId,
      recorder: conversation,
      costEstimator: costEstimator,
      budgetGuard: budgetGuard,
    );
  }
}
