import 'dart:async';
import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../client.dart';
import '../config.dart';
import '../errors.dart';
import '../protocol.dart';
import 'naming.dart';
import 'result.dart';
import 'risk.dart';
import 'schema.dart';

/// Called when the integration must be set to „Fehler“ (tools paused),
/// e.g. `ToolRegistry.reportError`.
typedef McpErrorReporter = void Function(String integrationId, String message);

/// Told after every tool call that reached the transport: `null` if the
/// server answered (also with a tool error), otherwise the failure. Lets
/// the app keep its stored status current without extra requests.
typedef McpCallObserver = void Function(McpException? failure);

/// Longest tool description passed on from the server.
const maxMcpDescription = 1024;

/// Most tools offered per server (context budget).
const maxToolsPerServer = 128;

/// A server tool that is not offered, with a German [reason].
final class McpSkippedTool {
  /// Creates the entry.
  const McpSkippedTool(this.name, this.reason);

  /// MCP tool name.
  final String name;

  /// Why it is left out.
  final String reason;

  @override
  String toString() => '$name: $reason';
}

/// One configured MCP server as an [Integration]: its tools land in the same
/// registry as the built-in ones (`mcp_<slug>__<tool>`).
///
/// The tool list is loaded with [loadTools] (cache first) before the
/// integration is registered; [tools] is synchronous and reflects the last
/// load. When the server reports `list_changed`, [loadTools] reloads and
/// [toolsChanged] fires – the app then registers the integration anew (the
/// registry copies the tools on registration).
final class McpIntegration implements Integration {
  /// Creates the integration for [client] (whose config is used).
  McpIntegration({required this.client, this.reportError, this.onCall}) {
    _changes = client.toolsChanged.listen((_) {
      unawaited(
        loadTools().then<void>(
          (_) {},
          onError: (Object e) => _setFailure(e is McpException ? e : null),
        ),
      );
    });
  }

  /// Setup step id for credentials or login.
  static const authStep = 'auth';

  /// The MCP client.
  final McpClient client;

  /// Sets the integration to „Fehler“ in the registry.
  final McpErrorReporter? reportError;

  /// Outcome of each tool call (see [McpCallObserver]).
  final McpCallObserver? onCall;

  late final StreamSubscription<void> _changes;
  final StreamController<void> _toolsChanged =
      StreamController<void>.broadcast();
  List<McpTool> _tools = const [];
  List<McpSkippedTool> _skipped = const [];
  bool _authFailed = false;

  /// The server config.
  McpServerConfig get config => client.config;

  /// Emits after [loadTools] changed [tools].
  Stream<void> get toolsChanged => _toolsChanged.stream;

  @override
  String get id => config.integrationId;

  @override
  String get displayName => config.name;

  @override
  String get iconId => 'mcp';

  @override
  Set<AppPlatform> get platforms => const {
    AppPlatform.android,
    AppPlatform.ios,
  };

  @override
  bool get sensitive => config.sensitive;

  @override
  List<SetupStep> get setup => [
    if (config.auth is! McpNoAuth)
      SetupStep(
        id: authStep,
        kind: SetupStepKind.login,
        label: config.auth is McpOAuth
            ? 'Beim Server anmelden'
            : 'Zugangsdaten eintragen',
      ),
  ];

  @override
  Future<SetupState> setupState() async {
    if (config.auth is McpNoAuth) return SetupState();
    final ok = !_authFailed && await _hasCredentials();
    return SetupState(missingSteps: [if (!ok) authStep]);
  }

  Future<bool> _hasCredentials() async {
    switch (config.auth) {
      case McpNoAuth():
        return true;
      case McpOAuth():
        final flow = client.oauth;
        return flow != null && await flow.hasUsableTokens(config);
      case final auth:
        for (final ref in auth.secretRefs) {
          final value = await client.secrets.read(ref);
          if (value == null || value.isEmpty) return false;
        }
        return true;
    }
  }

  /// Checks reachability: not reachable or not an MCP server → unavailable
  /// with the reason; missing credentials are handled by [setupState].
  @override
  Future<Availability> checkAvailability() async {
    if (!await _hasCredentials()) return Availability.yes;
    final probe = await client.probe();
    switch (probe.status) {
      case McpReachability.reachable:
        _authFailed = false;
        return Availability.yes;
      case McpReachability.authRequired:
        _authFailed = true;
        return Availability.yes;
      case McpReachability.unreachable:
        return Availability(
          available: false,
          reason: 'Nicht erreichbar: ${probe.detail}',
        );
      case McpReachability.protocolError:
        return Availability(
          available: false,
          reason: 'Kein gültiger MCP-Server: ${probe.detail}',
        );
    }
  }

  @override
  List<Tool> get tools => _tools;

  /// The tools as [McpTool]s (with original names and schema notes).
  List<McpTool> get mcpTools => _tools;

  /// Loads the tool list (cache unless [refresh]) and rebuilds [tools].
  Future<List<McpTool>> loadTools({bool refresh = false}) async {
    final List<McpToolInfo> infos;
    try {
      infos = await client.listTools(refresh: refresh);
    } on McpException catch (e) {
      _setFailure(e);
      rethrow;
    }
    _authFailed = false;
    _tools = buildTools(infos);
    if (!_toolsChanged.isClosed) _toolsChanged.add(null);
    return _tools;
  }

  /// Uses the cached tool list without contacting the server.
  Future<List<McpTool>> loadCachedTools() async {
    final cached = await client.cachedTools();
    if (cached != null) _tools = buildTools(cached.tools);
    return _tools;
  }

  /// Tools of the server that are not offered, with the reason (shown in
  /// the settings), as of the last [buildTools].
  List<McpSkippedTool> get skippedTools => _skipped;

  /// Maps [infos] onto tools (names, risk, overrides). Left out (and listed
  /// in [skippedTools]): tools the user switched off, repeated names (the
  /// first one wins), schemas over [maxSchemaBytes] and everything beyond
  /// [maxToolsPerServer] – these limits keep the model's context small.
  List<McpTool> buildTools(List<McpToolInfo> infos) {
    final names = McpNaming.toolNames(config.slug, infos.map((t) => t.name));
    final seen = <String>{};
    final tools = <McpTool>[];
    final skipped = <McpSkippedTool>[];
    for (final info in infos) {
      final override = config.toolOverrides[info.name];
      if (!seen.add(info.name)) {
        skipped.add(McpSkippedTool(info.name, 'Name doppelt vergeben'));
        continue;
      }
      if (!(override?.enabled ?? true)) {
        skipped.add(McpSkippedTool(info.name, 'abgeschaltet'));
        continue;
      }
      final tool = McpTool(
        integration: this,
        info: info,
        name: names[info.name]!,
        risk: mcpRisk(
          info.annotations,
          confirmAll: config.confirmAll,
          autoRun: override?.autoRun ?? false,
          override: override?.risk,
        ),
      );
      if (!tool._schema.withinBudget) {
        skipped.add(
          McpSkippedTool(
            info.name,
            'Schema zu groß (${tool._schema.encodedBytes ~/ 1024} KB, '
            'höchstens ${maxSchemaBytes ~/ 1024} KB)',
          ),
        );
        continue;
      }
      if (tools.length >= maxToolsPerServer) {
        skipped.add(
          McpSkippedTool(
            info.name,
            'mehr als $maxToolsPerServer Tools auf diesem Server',
          ),
        );
        continue;
      }
      tools.add(tool);
    }
    _skipped = List.unmodifiable(skipped);
    return List.unmodifiable(tools);
  }

  void _setFailure(McpException? e) {
    if (e == null || e.kind != McpErrorKind.authRequired) return;
    _authFailed = true;
    reportError?.call(id, 'Anmeldung nötig: ${e.message}');
  }

  /// Stops listening to the client.
  Future<void> dispose() async {
    await _changes.cancel();
    await _toolsChanged.close();
  }
}

/// One tool of an MCP server.
///
/// No undo (`ToolOutcome.undo` stays `null`): the effect happens on the
/// server and cannot be reverted by the app.
final class McpTool implements Tool {
  /// Creates the tool.
  McpTool({
    required this.integration,
    required this.info,
    required this.name,
    required this.risk,
  }) : _schema = McpSchema.from(info.inputSchema);

  /// Owning integration.
  final McpIntegration integration;

  /// The tool as listed by the server.
  final McpToolInfo info;

  final McpSchema _schema;

  @override
  final String name;

  @override
  final RiskLevel risk;

  /// Name on the server.
  String get mcpName => info.name;

  /// Schema parts the tool runtime does not enforce (see [McpSchema]).
  List<String> get unsupportedSchemaParts => _schema.unsupported;

  @override
  String get description {
    final text = info.description.trim().isEmpty
        ? (info.title ?? info.annotations.title ?? info.name)
        : info.description.trim();
    return text.length <= maxMcpDescription
        ? text
        : '${text.substring(0, maxMcpDescription - 1)}…';
  }

  @override
  Map<String, Object?> get inputSchema => _schema.schema;

  @override
  Future<ToolOutcome> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final server = integration.config.name;
    try {
      final result = await integration.client.callTool(
        info.name,
        args,
        cancel: ctx.cancel,
        idempotent: risk == RiskLevel.read,
      );
      integration.onCall?.call(null);
      return mcpOutcome(result, server: server, tool: info.name);
    } on McpException catch (e) {
      if (e.kind != McpErrorKind.cancelled) integration.onCall?.call(e);
      switch (e.kind) {
        case McpErrorKind.cancelled:
          return ToolOutcome.cancelled();
        case McpErrorKind.authRequired:
          integration._setFailure(e);
        default:
      }
      return ToolOutcome.error(
        'MCP-Server „$server“: ${e.message}',
        summary: '$server: Fehler',
      );
    }
  }

  @override
  String describeForConfirmation(Map<String, Object?> args) {
    final shown = args.isEmpty ? '' : ' ${ellipsize(jsonEncode(args), 120)}';
    return '${integration.config.name}: ${info.name}$shown';
  }

  @override
  String toString() => 'McpTool($name → ${info.name}, ${risk.name})';
}
