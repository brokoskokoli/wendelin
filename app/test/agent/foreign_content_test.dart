import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

/// WP157 / ADR 0023: after foreign content (a result that is not trusted)
/// a tool with a network target asks first, in the same run and in the rest
/// of the conversation (the history still holds the foreign text); a tool
/// without a network target does not; a new conversation starts clean.

/// Wraps a [FakeTool] with extra markers: see the subclasses.
base class _Wrapped implements Tool {
  _Wrapped(this.inner);

  final FakeTool inner;

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

/// Own data, no network target (notes, calendar …).
final class _Local extends _Wrapped
    implements TrustedContentSource, NoNetworkTarget {
  _Local(super.inner);
}

/// Trust follows the user's tick (HTTP tool, MCP server), network target.
final class _Aware extends _Wrapped implements ContentTrustAware {
  _Aware(super.inner, {required this.mayContainUntrustedContent});

  @override
  final bool mayContainUntrustedContent;
}

void main() {
  const device = DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin');

  FakeTool plain(String name) => FakeTool(name: name);

  /// Runs [firstTurns] of tool calls and returns the names asked about.
  Future<List<String>> run(
    List<Tool> tools,
    List<String> calls, {
    InMemoryConversation? conversation,
    String session = 's1',
  }) async {
    final catalog = FakeToolCatalog(tools);
    final clock = FixedClock(DateTime.utc(2026, 10, 26, 9));
    final conv = conversation ?? InMemoryConversation();
    final target = ProviderTarget(
      profileId: 'p',
      modelId: 'm',
      provider: FakeLlmProvider([
        for (final c in calls)
          ScriptedTurn.toolCalls([
            ToolCallBlock(id: 'id_$c', name: c, argumentsJson: '{}'),
          ]),
        ScriptedTurn.text('Fertig.'),
      ]),
      privacy: PrivacyLevel.standard,
    );
    final runner = AgentRunner(
      resolver: _Fixed(target),
      contextBuilder: ContextBuilder(
        config: const AgentConfig(),
        clock: clock,
        device: device,
        catalog: catalog,
        history: conv,
      ),
      invoker: ToolExecutor(catalog: catalog, policy: RiskPolicy()),
      clock: clock,
      sessionId: session,
      recorder: conv,
    );
    final asked = <String>[];
    await for (final e in runner.run(UserInput(text: 'Los'))) {
      if (e is ConfirmationRequired) {
        asked.add(e.call.name);
        e.respond(true);
      }
    }
    return asked;
  }

  List<Tool> catalogTools() => [
    plain('web__search'),
    plain('http__x'),
    _Local(FakeTool(name: 'notes__read')),
    _Aware(plain('mcp__safe'), mayContainUntrustedContent: false),
    _Aware(plain('mcp__open'), mayContainUntrustedContent: true),
  ];

  test('nach Websuche fragt ein Netz-Tool nach, ein lokales Tool nicht', () {
    expect(
      run(catalogTools(), ['web__search', 'http__x', 'notes__read']),
      completion(['http__x']),
    );
  });

  test('ohne fremde Inhalte läuft das Netz-Tool ohne Rückfrage', () {
    expect(
      run(catalogTools(), ['notes__read', 'http__x']),
      completion(isEmpty),
    );
  });

  test('als sicher markierter MCP-Server: Ergebnis zählt nicht als fremd', () {
    expect(run(catalogTools(), ['mcp__safe', 'http__x']), completion(isEmpty));
  });

  test('MCP-Server mit Haken (Standard): Ergebnis ist fremd', () {
    expect(
      run(catalogTools(), ['mcp__open', 'http__x']),
      completion(['http__x']),
    );
  });

  test('Fehlertext gilt als fremd, auch von einem sicheren Tool', () {
    final failing = _Local(
      FakeTool(
        name: 'notes__fail',
        handler: (args, ctx) async => ToolOutcome.error('kaputt'),
      ),
    );
    expect(
      run([failing, plain('http__x')], ['notes__fail', 'http__x']),
      completion(['http__x']),
    );
  });

  test('der Verlauf der Unterhaltung behält das Fremde, neue Unterhaltung '
      'beginnt sauber', () async {
    final conv = InMemoryConversation();
    expect(
      await run(catalogTools(), ['web__search'], conversation: conv),
      <String>[],
    );
    // Next message of the same conversation: the injection is still in the
    // context, so the network tool asks although this run saw nothing foreign.
    expect(await run(catalogTools(), ['http__x'], conversation: conv), [
      'http__x',
    ]);
    // New conversation: empty history.
    expect(
      await run(
        catalogTools(),
        ['http__x'],
        conversation: InMemoryConversation(),
        session: 's2',
      ),
      isEmpty,
    );
  });

  group('tools__search: fremd nur bei unsicheren MCP/HTTP-Treffern', () {
    final hits = <String, Tool>{
      'web__search': plain('web__search'),
      'web__fetch': plain('web__fetch'),
      'notes__read': _Local(FakeTool(name: 'notes__read')),
      'mcp__safe': _Aware(
        plain('mcp__safe'),
        mayContainUntrustedContent: false,
      ),
      'mcp__open': _Aware(plain('mcp__open'), mayContainUntrustedContent: true),
      'unknown__x': plain('unknown__x'),
    };
    final search = ToolSearchTool(
      candidates: [
        for (final t in hits.values)
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
    final catalog = FakeToolCatalog([search]);

    bool trusted(List<String> names, {bool error = false}) {
      final text = jsonEncode({
        'tools': [
          for (final n in names) {'name': n},
        ],
      });
      return isTrustedResult(
        catalog,
        ToolSearchTool.toolName,
        isError: error,
        content: [TextBlock(text)],
      );
    }

    // (Treffer, vertraut?)
    final table = <(List<String>, bool)>[
      (const [], true),
      (['notes__read'], true),
      (['web__search', 'web__fetch'], true),
      (['mcp__safe'], true),
      (['notes__read', 'mcp__safe', 'web__search'], true),
      (['mcp__open'], false),
      (['notes__read', 'mcp__open'], false),
      // Fail-closed: Herkunft unbekannt / nicht im Katalog.
      (['unknown__x'], false),
      (['gibt_es_nicht'], false),
    ];
    for (final (names, expected) in table) {
      test('Treffer $names → ${expected ? 'sicher' : 'fremd'}', () {
        expect(trusted(names), expected);
      });
    }

    test('Fehler und unlesbares Ergebnis sind fremd', () {
      expect(trusted(['notes__read'], error: true), isFalse);
      expect(
        isTrustedResult(
          catalog,
          ToolSearchTool.toolName,
          content: [const TextBlock('kein json')],
        ),
        isFalse,
      );
      expect(
        isTrustedResult(catalog, ToolSearchTool.toolName),
        isFalse,
        reason: 'ohne Inhalt',
      );
    });

    test(
      'im Verlauf: Suche mit unsicherem Treffer macht den Verlauf fremd',
      () {
        Message result(String id, List<String> names) => Message.toolResults([
          ToolResultBlock(
            callId: id,
            content: [
              TextBlock(
                jsonEncode({
                  'tools': [
                    for (final n in names) {'name': n},
                  ],
                }),
              ),
            ],
          ),
        ]);
        Message call(String id) => Message.assistant([
          ToolCallBlock(
            id: id,
            name: ToolSearchTool.toolName,
            argumentsJson: '{}',
          ),
        ]);
        expect(
          hasUntrustedResult(catalog, [
            call('1'),
            result('1', ['notes__read']),
          ]),
          isFalse,
        );
        expect(
          hasUntrustedResult(catalog, [
            call('1'),
            result('1', ['mcp__open']),
          ]),
          isTrue,
        );
      },
    );
  });
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
