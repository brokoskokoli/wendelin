import 'package:test/test.dart';
import 'package:wendelin_agent/src/run/run_state.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

/// WP201: the run carries the origin of its untrusted results next to the
/// flag and hands it to the policy (effectiveRisk) and to the tool context.

/// Stands in for an `McpTool`: untrusted results, names its server.
final class _Srv implements Tool, ContentTrustAware, ContentOriginAware {
  _Srv(String name, this.id) : inner = FakeTool(name: name);

  final String id;
  final FakeTool inner;

  @override
  bool get mayContainUntrustedContent => true;
  @override
  ContentOrigin get contentOrigin => ContentOrigin.server(id);
  @override
  String get name => inner.name;
  @override
  String get description => inner.description;
  @override
  Map<String, Object?> get inputSchema => inner.inputSchema;
  @override
  RiskLevel get risk => inner.risk;
  @override
  Future<ToolOutcome> execute(Map<String, Object?> args, ToolContext ctx) =>
      inner.execute(args, ctx);
  @override
  String describeForConfirmation(Map<String, Object?> args) =>
      inner.describeForConfirmation(args);
}

/// Records what the runner hands to the policy and to the tools.
final class _Recording implements ToolInvoker, ToolRiskAssessor {
  _Recording(this.inner);

  final FakeToolInvoker inner;
  final assessed = <(String, ContentOrigin, bool)>[];
  final contexts = <(String, ContentOrigin, bool)>[];

  @override
  RiskLevel effectiveRisk(
    Tool tool,
    String sessionId, {
    bool foreignContent = false,
    ContentOrigin foreignOrigin = ContentOrigin.none,
  }) {
    assessed.add((tool.name, foreignOrigin, foreignContent));
    return tool.risk;
  }

  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> calls,
    ToolContext ctx,
  ) {
    for (final c in calls) {
      contexts.add((c.name, ctx.foreignOrigin, ctx.foreignContentSeen));
    }
    return inner.invokeAll(calls, ctx);
  }
}

/// Puts a provider block (server-side web search) before the answer of the
/// call with index [at].
final class _WithProviderBlock implements LlmProvider {
  _WithProviderBlock(this.inner, this.at);

  final LlmProvider inner;
  final int at;
  int _n = 0;

  @override
  ProviderType get type => inner.type;
  @override
  ProviderCapabilities get caps => inner.caps;
  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) async* {
    if (_n++ == at) {
      yield const ProviderBlockComplete(
        ProviderBlock(provider: 'anthropic', rawJson: '{}'),
      );
    }
    yield* inner.chat(req, cancel: cancel);
  }

  @override
  Future<List<ModelInfo>> listModels() => inner.listModels();
  @override
  Future<HealthCheck> test() => inner.test();
}

void main() {
  /// Runs [calls] one per model turn; returns what the last call saw.
  Future<_Recording> run(
    List<Tool> tools,
    List<String> calls, {
    int? providerBlockBeforeTurn,
  }) async {
    var n = 0;
    final fake = FakeLlmProvider([
      for (final c in calls) ScriptedTurn.toolCalls([call('id_${n++}', c)]),
      ScriptedTurn.text('Fertig.'),
    ]);
    final invoker = _Recording(FakeToolInvoker(FakeToolCatalog(tools)));
    final h = Harness(
      invoker: invoker,
      tools: tools,
      primary: ProviderTarget(
        profileId: 'p',
        modelId: 'm',
        provider: providerBlockBeforeTurn == null
            ? fake
            : _WithProviderBlock(fake, providerBlockBeforeTurn),
        privacy: PrivacyLevel.standard,
      ),
    );
    await h.runner.run(UserInput(text: 'Los')).drain<void>();
    return invoker;
  }

  final x = _Srv('x__a', 'X');
  final y = _Srv('y__a', 'Y');
  const fromX = ContentOrigin.server('X');

  test('vor jedem Fremden: none; danach X in Policy und ToolContext', () async {
    final r = await run([x], ['x__a', 'x__a']);
    expect(r.contexts, [
      ('x__a', ContentOrigin.none, false),
      ('x__a', fromX, true),
    ]);
    expect(r.assessed.last, ('x__a', fromX, true));
  });

  test('X dann Y: unbekannt', () async {
    final r = await run([x, y], ['x__a', 'y__a', 'x__a']);
    expect(r.contexts.last, ('x__a', ContentOrigin.unknown, true));
    expect(r.assessed.last, ('x__a', ContentOrigin.unknown, true));
  });

  test('Fremdes ohne Herkunftsangabe: unbekannt, nie ein Server', () async {
    final r = await run(
      [x, FakeTool(name: 'web__search')],
      ['x__a', 'web__search', 'x__a'],
    );
    expect(r.contexts.last, ('x__a', ContentOrigin.unknown, true));
  });

  test('Anbieter-Block im Lauf nach X: unbekannt', () async {
    final r = await run([x], ['x__a', 'x__a'], providerBlockBeforeTurn: 1);
    expect(r.contexts.last, ('x__a', ContentOrigin.unknown, true));
  });

  test('untrustedSeen ohne Herkunft ergibt nie einen Server (unbekannt)', () {
    final s = RunState(null)..untrustedSeen = true;
    expect(s.foreignOriginForTools, ContentOrigin.unknown);
    s.foreignOrigin = fromX;
    expect(s.foreignOriginForTools, fromX);
    expect(RunState(null).foreignOriginForTools, ContentOrigin.none);
  });
}
