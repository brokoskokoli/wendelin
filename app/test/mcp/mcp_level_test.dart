// WP160 Teil 2c: MCP-Tools haben dieselbe Stufenauswahl A–D wie die
// eingebauten (ADR 0022).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/ui/settings/mcp/mcp_server_detail_screen.dart';
import 'package:wendelin/ui/settings/mcp/mcp_servers_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../settings/integrations_screen_test.dart' show settle;
import '../support/mcp_support.dart';
import '../support/test_env.dart';
import '../ui/helpers.dart' show setView;
import 'mcp_screens_test.dart' show containerOf, pumpUntil, tapText;

const _read = 'mcp_homeserver__get_state';
const _write = 'mcp_homeserver__set_light';
const _external = 'mcp_homeserver__delete_scene';

Finder _key(String k) => find.byKey(ValueKey(k));

Future<ProviderContainer> _open(
  WidgetTester tester, {
  ToolPrefs prefs = const ToolPrefs(),
  Map<String, McpToolOverride> overrides = const {},
  bool confirmAll = false,
}) async {
  final env = TestEnv(
    enabled: const {'mcp_homeserver'},
    extraOverrides: mcpOverrides(),
    startup: StartupSettings(
      enabledIntegrations: const {'mcp_homeserver'},
      toolPrefs: prefs,
    ),
  );
  await tester.runAsync(
    () => seedServers(
      env,
      [
        (
          config: McpServerConfig(
            id: 'srv',
            name: 'Homeserver',
            slug: 'homeserver',
            url: Uri.parse('http://homeserver.local:3000/mcp'),
            auth: McpBearerAuth(McpSecretRefs.bearer('srv')),
            toolOverrides: overrides,
            confirmAll: confirmAll,
          ),
          tools: homeToolInfos(),
          check: null,
        ),
      ],
      secrets: {McpSecretRefs.bearer('srv'): 'token'},
    ),
  );
  setView(tester, const Size(390, 1800));
  await tester.pumpWidget(env.app(home: const McpServersScreen()));
  final c = containerOf(tester, McpServersScreen);
  await pumpUntil(tester, () {
    final tools = c.read(toolRegistryProvider).integrations;
    return tools.any((i) => i.integration.tools.any((t) => t.name == _read));
  });
  await settle(tester);
  await tapText(tester, 'Homeserver');
  expect(find.byType(McpServerDetailScreen), findsOneWidget);
  return c;
}

Future<void> _sheet(WidgetTester tester, String tool) async {
  await tapText(tester, tool);
}

String _head(WidgetTester tester, String name) => tester
    .widget<Text>(
      find.descendant(
        of: _key('levelDetails_$name'),
        matching: find.byType(Text),
      ),
    )
    .data!;

Future<void> _choose(WidgetTester tester, String name, String level) async {
  if (_key('level_${name}_$level').evaluate().isEmpty) {
    await tester.tap(_key('levelDetails_$name'));
    await settle(tester);
  }
  await tester.ensureVisible(_key('level_${name}_$level'));
  await tester.tap(_key('level_${name}_$level'));
  await settle(tester);
}

Map<String, String> _levels(ProviderContainer c) =>
    c.read(toolPrefsProvider).levels;

void main() {
  setUp(allowRealHttp);

  testWidgets('Picker sichtbar mit Standard aus dem Risiko, Wahl speichert, '
      'Standard stellt wieder her', (tester) async {
    final c = await _open(tester);
    await _sheet(tester, 'get_state');
    // read = C.
    expect(_head(tester, _read), 'Details · Stufe C · Standard');
    await _choose(tester, _read, 'a');
    expect(_levels(c), {_read: 'a'});
    expect(_head(tester, _read), 'Details · Stufe A · geändert');
    await tester.tap(_key('levelRestore_$_read'));
    await settle(tester);
    expect(_levels(c), isEmpty);
    expect(_head(tester, _read), 'Details · Stufe C · Standard');
    // Die Stufe ersetzt die alte Risikoauswahl nicht: sie steht daneben.
    expect(find.text('Immer nachfragen'), findsOneWidget);
  });

  testWidgets('write ohne „ohne Nachfrage“ und external: Standard D, Lockern '
      'fragt vorher, Abbrechen speichert nichts', (tester) async {
    final c = await _open(tester);
    await _sheet(tester, 'set_light');
    expect(_head(tester, _write), 'Details · Stufe D · Standard');
    await _choose(tester, _write, 'c');
    expect(find.text('Weniger Schutz?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(_levels(c), isEmpty);
    await _choose(tester, _write, 'c');
    await tester.tap(find.text('Trotzdem ändern'));
    await settle(tester);
    expect(_levels(c), {_write: 'c'});
    // Verschärfen fragt nie.
    await _choose(tester, _write, 'd');
    expect(find.text('Weniger Schutz?'), findsNothing);
    expect(_levels(c), {_write: 'd'});
  });

  testWidgets('Kaputter Wert zeigt D, nie den Standard', (tester) async {
    await _open(tester, prefs: const ToolPrefs(levels: {_read: 'x'}));
    await _sheet(tester, 'get_state');
    expect(_head(tester, _read), 'Details · Stufe D · geändert');
  });

  testWidgets('Migration lockert nichts: alte Risikowerte bestimmen nur den '
      'Standard, „immer bestätigen“ ist D', (tester) async {
    await _open(
      tester,
      prefs: const ToolPrefs(alwaysConfirm: {_read}),
      overrides: {
        // altes „ohne Nachfrage“ auf write: Standard C wie bisher (lief frei)
        'set_light': const McpToolOverride(autoRun: true),
        // alte Verschärfung auf read: Standard D wie bisher (fragte immer)
        'get_state': const McpToolOverride(risk: RiskLevel.external),
      },
    );
    await _sheet(tester, 'set_light');
    expect(_head(tester, _write), 'Details · Stufe C · Standard');
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    // „immer bestätigen“ (D) gewinnt über den Standard des Risikos.
    await _sheet(tester, 'get_state');
    expect(_head(tester, _read), 'Details · Stufe D · geändert');
  });

  testWidgets('Unter „Alle Tools bestätigen“ gibt es keinen Picker', (
    tester,
  ) async {
    await _open(tester, confirmAll: true);
    await _sheet(tester, 'get_state');
    expect(_key('levelDetails_$_read'), findsNothing);
  });

  testWidgets('Gesperrt läuft ein MCP-Tool nur auf A und nur ohne Stimme '
      'nach der Tabelle wie jedes Tool', (tester) async {
    final c = await _open(tester);
    final tool = c
        .read(toolRegistryProvider)
        .integrations
        .expand((i) => i.integration.tools)
        .firstWhere((t) => t.name == _read);
    final policy = c.read(riskPolicyProvider);
    const locked = AccessContext.lockedUnknownVoice;
    const voice = AccessContext(locked: true, speakerRecognized: true);
    Future<void> set(String? level) => c
        .read(toolPrefsProvider.notifier)
        .set(ToolPrefs(levels: {_read: ?level}));
    await set(null);
    expect(policy.decide(tool, 's', access: locked), PolicyDecision.unlock);
    await set('b');
    expect(policy.decide(tool, 's', access: locked), PolicyDecision.unlock);
    expect(policy.decide(tool, 's', access: voice), PolicyDecision.allow);
    await set('a');
    expect(policy.decide(tool, 's', access: locked), PolicyDecision.allow);
    await set('x');
    expect(policy.decide(tool, 's', access: locked), PolicyDecision.unlock);
  });

  testWidgets('external-Tool: Standard D, Lockern auf B warnt', (tester) async {
    final c = await _open(tester);
    await _sheet(tester, 'delete_scene');
    expect(_head(tester, _external), 'Details · Stufe D · Standard');
    await _choose(tester, _external, 'b');
    expect(find.text('Weniger Schutz?'), findsOneWidget);
    await tester.tap(find.text('Trotzdem ändern'));
    await settle(tester);
    expect(_levels(c), {_external: 'b'});
  });
}
