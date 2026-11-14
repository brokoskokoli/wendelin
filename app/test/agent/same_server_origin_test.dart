import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

/// WP201 / ADR 0023: after foreign content that came only from the MCP
/// server X, a tool of X with level „Ohne Nachfrage“ runs without asking
/// (same run, history, new run of the same conversation). Every other
/// origin (server Y, web search, unknown, mixed) keeps the confirmation.

/// Stands in for an `McpTool`: untrusted results, names its server.
final class _ServerTool implements Tool, ContentTrustAware, ContentOriginAware {
  _ServerTool(this.serverId, String name, {RiskLevel risk = RiskLevel.write})
    : inner = FakeTool(name: name, risk: risk);

  final String serverId;
  final FakeTool inner;

  @override
  bool get mayContainUntrustedContent => true;
  @override
  ContentOrigin get contentOrigin => ContentOrigin.server(serverId);
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

void main() {
  const device = DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin');

  final xList = _ServerTool('X', 'mcp_x__list', risk: RiskLevel.read);
  final xSet = _ServerTool('X', 'mcp_x__set');
  final yList = _ServerTool('Y', 'mcp_y__list', risk: RiskLevel.read);
  // Web search: untrusted, no origin interface -> unknown.
  final web = FakeTool(name: 'web__search');

  late List<Tool> extra;
  setUp(() => extra = []);

  /// Runs [calls] (name, args json) and returns the names asked about.
  Future<List<String>> run(
    List<(String, String)> calls, {
    InMemoryConversation? conversation,
  }) async {
    final all = [xList, xSet, yList, web, ...extra];
    final catalog = FakeToolCatalog(all);
    final clock = FixedClock(DateTime.utc(2026, 11, 14, 9));
    final conv = conversation ?? InMemoryConversation();
    var n = 0;
    final target = ProviderTarget(
      profileId: 'p',
      modelId: 'm',
      provider: FakeLlmProvider([
        for (final (name, args) in calls)
          ScriptedTurn.toolCalls([
            ToolCallBlock(id: 'id_${n++}', name: name, argumentsJson: args),
          ]),
        ScriptedTurn.text('Fertig.'),
      ]),
      privacy: PrivacyLevel.standard,
    );
    final policy = RiskPolicy()
      ..setLevel(xSet.name, SecurityLevel.a)
      ..setLevel(xList.name, SecurityLevel.a);
    final runner = AgentRunner(
      resolver: _Fixed(target),
      contextBuilder: ContextBuilder(
        config: const AgentConfig(),
        clock: clock,
        device: device,
        catalog: catalog,
        history: conv,
      ),
      invoker: ToolExecutor(catalog: catalog, policy: policy),
      clock: clock,
      sessionId: 's1',
      recorder: conv,
    );
    final asked = <String>[];
    await for (final e in runner.run(UserInput(text: 'Los'))) {
      if (e is ConfirmationRequired) {
        if (e.call.name == xSet.name) asked.add(e.call.name);
        e.respond(true);
      }
    }
    return asked;
  }

  (String, String) c(String name) => (name, '{}');

  test('X -> X: Tool von X läuft ohne Nachfrage', () {
    expect(run([c('mcp_x__list'), c('mcp_x__set')]), completion(isEmpty));
  });

  test('Y -> X: Tool von X fragt nach', () {
    expect(
      run([c('mcp_y__list'), c('mcp_x__set')]),
      completion(['mcp_x__set']),
    );
  });

  test('X und Y gemischt -> X: fragt nach', () {
    expect(
      run([c('mcp_x__list'), c('mcp_y__list'), c('mcp_x__set')]),
      completion(['mcp_x__set']),
    );
  });

  test('Websuche (unbekannte Herkunft) -> X: fragt nach', () {
    expect(
      run([c('web__search'), c('mcp_x__set')]),
      completion(['mcp_x__set']),
    );
  });

  test('Fehlertext eines Tools von X zählt als unbekannt: fragt nach', () {
    final failTool = _FailingServerTool('X', 'mcp_x__fail2');
    extra = [failTool];
    expect(
      run([c('mcp_x__fail2'), c('mcp_x__set')]),
      completion(['mcp_x__set']),
    );
  });

  group('tools__search', () {
    ToolSearchTool searchOver(List<Tool> hits) => ToolSearchTool(
      candidates: [
        for (final t in hits)
          (
            integration: FakeIntegration(
              id: t.name.split('__').first,
              tools: [t],
            ),
            tool: t,
          ),
      ],
      unlock: (_, _) {},
    );

    (String, String) searchFor(String q) =>
        (ToolSearchTool.toolName, jsonEncode({'query': q}));

    test('Treffer nur von X: Herkunft X, Tool von X ohne Nachfrage', () {
      extra = [
        searchOver([xList, xSet]),
      ];
      expect(run([searchFor('x'), c('mcp_x__set')]), completion(isEmpty));
    });

    test('Treffer von X und Y gemischt: fragt nach', () {
      extra = [
        searchOver([xList, xSet, yList]),
      ];
      expect(
        run([searchFor('list'), c('mcp_x__set')]),
        completion(['mcp_x__set']),
      );
    });

    test(
      'Treffer von X und einem Tool ohne Herkunft: unbekannt, fragt nach',
      () {
        extra = [
          searchOver([xList, FakeTool(name: 'other__tool')]),
        ];
        expect(
          run([searchFor('s'), c('mcp_x__set')]),
          completion(['mcp_x__set']),
        );
      },
    );

    test('Suche ohne Treffer: nichts Fremdes, keine Herkunft nötig', () {
      extra = [
        searchOver([xList]),
      ];
      expect(run([searchFor('qqqq'), c('mcp_x__set')]), completion(isEmpty));
    });
  });

  group('Fortsetzung: Herkunft aus dem Verlauf', () {
    test('Verlauf nur von X: nächster Lauf ohne Nachfrage', () async {
      final conv = InMemoryConversation();
      expect(await run([c('mcp_x__list')], conversation: conv), isEmpty);
      expect(await run([c('mcp_x__set')], conversation: conv), isEmpty);
    });

    test('Verlauf von Y: nächster Lauf fragt für X nach', () async {
      final conv = InMemoryConversation();
      expect(await run([c('mcp_y__list')], conversation: conv), isEmpty);
      expect(await run([c('mcp_x__set')], conversation: conv), ['mcp_x__set']);
    });

    test(
      'Verlauf unbekannt (Websuche) bleibt unbekannt, auch nach X',
      () async {
        final conv = InMemoryConversation();
        await run([c('web__search')], conversation: conv);
        // A later result of X must not turn "unknown" into "X".
        expect(
          await run([c('mcp_x__list'), c('mcp_x__set')], conversation: conv),
          ['mcp_x__set'],
        );
      },
    );

    test('X im Verlauf, Y im neuen Lauf: gemischt, fragt nach', () async {
      final conv = InMemoryConversation();
      await run([c('mcp_x__list')], conversation: conv);
      expect(
        await run([c('mcp_y__list'), c('mcp_x__set')], conversation: conv),
        ['mcp_x__set'],
      );
    });

    test('neue Unterhaltung beginnt ohne Herkunft', () async {
      await run([c('web__search')]);
      expect(await run([c('mcp_x__set')]), isEmpty);
    });
  });
}

final class _FailingServerTool extends _ServerTool {
  _FailingServerTool(super.serverId, super.name);

  @override
  Future<ToolOutcome> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => ToolOutcome.error('kaputt');
}

final class _Fixed implements ProviderResolver {
  _Fixed(this.target);

  final ProviderTarget target;

  @override
  Resolution resolve(UserInput input) =>
      Resolution(target: target, reason: 'Standard');

  @override
  Resolution? escalate(Resolution current, EscalationReason reason) => null;
}
