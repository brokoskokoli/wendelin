import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import 'audit_recorder.dart';
import 'provider_config.dart';
import 'storage_adapters.dart';

/// Builds one [AgentRun] per request, wired to the registry, the local
/// database and the audit log.
final class AgentFactory {
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
  /// The tool catalog is built for the lowest privacy level of all targets
  /// (see [ProviderConfig.lowestPrivacy]). Memory entries go into the
  /// prompt only if that catalog offers the memory integration, i.e. it is
  /// active and allowed for this privacy level.
  AgentRun create(ProviderConfig providers, String sessionId) {
    final catalog = registry.catalogFor(
      providers.lowestPrivacy,
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
      invoker: ToolExecutor(catalog: catalog, policy: policy, audit: audit),
      clock: clock,
      sessionId: sessionId,
      recorder: conversation,
      costEstimator: costEstimator,
      budgetGuard: budgetGuard,
    );
  }
}
