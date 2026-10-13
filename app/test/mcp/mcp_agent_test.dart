import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../agent/agent_controller_test.dart' show sendAndWait, waitFor;
import '../support/mcp_support.dart';
import '../support/test_env.dart';

/// The agent with a scripted model and an MCP server (WP27).
void main() {
  late FakeMcpServer server;
  late TestEnv env;
  late ProviderContainer c;

  setUp(() async {
    allowRealHttp();
    server = await FakeMcpServer.start(tools: homeTools());
  });

  tearDown(() async {
    c.dispose();
    await server.close();
  });

  Future<FakeLlmProvider> start(
    List<ScriptedTurn> turns, {
    PrivacyLevel privacy = PrivacyLevel.standard,
    bool sensitive = false,
  }) async {
    final provider = FakeLlmProvider(turns);
    env = TestEnv(
      enabled: const {},
      providerConfig: scripted(provider, privacy: privacy),
      extraOverrides: mcpOverrides(),
    );
    c = env.container();
    await addAndEnable(c, draftFor(server, sensitive: sensitive));
    return provider;
  }

  String toolResult(ChatRequest request) => [
    for (final m in request.messages)
      for (final b in m.content)
        if (b is ToolResultBlock) jsonEncode(b.toJson()),
  ].join();

  test('Modell ruft mcp_<server>__<tool> auf, Ergebnis in der Daten-Hülle, '
      'Audit nennt den Server', () async {
    final provider = await start([
      ScriptedTurn.toolCalls([
        call('c1', 'mcp_homeserver__get_state', '{"entity":"licht.kueche"}'),
      ]),
      ScriptedTurn.text('Das Küchenlicht ist an.'),
    ]);
    await sendAndWait(c, 'Ist das Küchenlicht an?');
    expect(
      provider.requests.first.tools.map((t) => t.name),
      contains('mcp_homeserver__get_state'),
    );
    final result = toolResult(provider.requests[1]);
    expect(
      result,
      contains('<mcp_result server=\\"Homeserver\\" tool=\\"get_state\\"'),
    );
    expect(result, contains('licht.kueche: an'));
    final calls = server.requests.where((r) => r.rpcMethod == 'tools/call');
    expect(calls.single.body, contains('licht.kueche'));

    final audit = await env.storage.audit.query(
      const AuditFilter(kinds: {AuditKind.toolCall}),
    );
    expect(audit.single.payload['tool'], 'mcp_homeserver__get_state');
    expect(audit.single.payload['status'], 'ok');
  });

  test('external (destruktiv): Bestätigungskarte nennt den Server, „Nein“ '
      'ruft den Server nicht', () async {
    await start([
      ScriptedTurn.toolCalls([
        call('c1', 'mcp_homeserver__delete_scene', '{"scene":"abend"}'),
      ]),
      ScriptedTurn.text('Gut, ich lasse sie.'),
    ]);
    final controller = c.read(agentControllerProvider.notifier);
    await controller.send('Lösch die Abendszene');
    final asking = await waitFor(c, (s) => s.pending != null);
    final question = asking.pending! as ToolQuestion;
    expect(question.event.risk, RiskLevel.external);
    expect(question.event.description, startsWith('Homeserver: delete_scene'));
    controller.answer(approved: false);
    await controller.idle;
    expect(server.requests.where((r) => r.rpcMethod == 'tools/call'), isEmpty);
  });

  test('write ohne Undo fragt ebenfalls nach', () async {
    await start([
      ScriptedTurn.toolCalls([call('c1', 'mcp_homeserver__set_light', '{}')]),
      ScriptedTurn.text('Licht ist an.'),
    ]);
    final controller = c.read(agentControllerProvider.notifier);
    await controller.send('Mach Licht');
    final asking = await waitFor(c, (s) => s.pending != null);
    expect((asking.pending! as ToolQuestion).event.risk, RiskLevel.external);
    controller.answer(approved: true);
    await controller.idle;
    expect(
      server.requests.where((r) => r.rpcMethod == 'tools/call'),
      hasLength(1),
    );
  });

  test('sensibler Server wird Standard-Zielen nicht angeboten (K10), dem '
      'TEE-Ziel schon', () async {
    final provider = await start([
      ScriptedTurn.toolCalls([
        call('c1', 'mcp_homeserver__get_state', '{"entity":"tür"}'),
      ]),
      ScriptedTurn.text('Geht nicht.'),
    ], sensitive: true);
    c.read(toolRegistryProvider).sensitiveMinimum = PrivacyLevel.tee;
    await sendAndWait(c, 'Ist die Tür zu?');
    expect(
      provider.requests.first.tools.where((t) => t.name.startsWith('mcp_')),
      isEmpty,
    );
    expect(server.requests.where((r) => r.rpcMethod == 'tools/call'), isEmpty);
    final audit = await env.storage.audit.query(
      const AuditFilter(kinds: {AuditKind.toolCall}),
    );
    expect(audit.single.payload['status'], 'denied');

    c.dispose();
    final tee = FakeLlmProvider([ScriptedTurn.text('ok')]);
    env = TestEnv(
      enabled: const {},
      providerConfig: scripted(tee, privacy: PrivacyLevel.tee),
      extraOverrides: mcpOverrides(),
      storage: env.storage,
    );
    c = env.container();
    await addAndEnable(c, draftFor(server, name: 'Tür', sensitive: true));
    c.read(toolRegistryProvider).sensitiveMinimum = PrivacyLevel.tee;
    await sendAndWait(c, 'Hallo');
    expect(
      tee.requests.first.tools.map((t) => t.name),
      contains('mcp_tuer__get_state'),
    );
  });
}
