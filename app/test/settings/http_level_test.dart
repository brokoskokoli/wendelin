// WP160 Teil 2c: HTTP-Tools haben dieselbe Stufenauswahl A–D wie die
// eingebauten (ADR 0022).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../support/http_tools_support.dart';
import '../support/test_env.dart';
import 'http_tools_screen_test.dart'
    show enter, fillLicht, pumpHttpTools, syncSettle;
import 'integrations_screen_test.dart' show settle;

const _tool = 'http__licht';

Finder _key(String k) => find.byKey(ValueKey(k));

String _head(WidgetTester tester, [String name = _tool]) => tester
    .widget<Text>(
      find.descendant(
        of: _key('levelDetails_$name'),
        matching: find.byType(Text),
      ),
    )
    .data!;

Future<void> _choose(WidgetTester tester, String level) async {
  if (_key('level_${_tool}_$level').evaluate().isEmpty) {
    await tester.ensureVisible(_key('levelDetails_$_tool'));
    await tester.tap(_key('levelDetails_$_tool'));
    await settle(tester);
  }
  await tester.ensureVisible(_key('level_${_tool}_$level'));
  await tester.tap(_key('level_${_tool}_$level'));
  await settle(tester);
}

TestEnv _env(ToolPrefs prefs) =>
    TestEnv(startup: StartupSettings(toolPrefs: prefs));

Map<String, String> _levels(ProviderContainer c) =>
    c.read(toolPrefsProvider).levels;

void _back(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text(_tool));
  await settle(tester);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Speichern'));
  await settle(tester);
  await syncSettle(tester);
}

void main() {
  testWidgets('Neues Tool: ohne Namen kein Picker; mit Namen Standard aus dem '
      'Risiko; Wahl wird erst mit dem Tool gespeichert', (tester) async {
    final env = _env(const ToolPrefs());
    final c = await pumpHttpTools(tester, env);
    await tester.tap(find.text('+ HTTP-Tool'));
    await settle(tester);
    expect(_key('levelDetails_$_tool'), findsNothing);
    _back(tester);
    await settle(tester);
    await fillLicht(tester);
    // POST ohne „ohne Nachfrage“ = external = D.
    expect(_head(tester), 'Details · Stufe D · Standard');
    await _choose(tester, 'c');
    expect(find.text('Weniger Schutz?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(_head(tester), 'Details · Stufe D · Standard');
    await _choose(tester, 'c');
    await tester.tap(find.text('Trotzdem ändern'));
    await settle(tester);
    expect(_head(tester), 'Details · Stufe C · geändert');
    expect(_levels(c), isEmpty, reason: 'erst beim Speichern');
    await _save(tester);
    expect(_levels(c), {_tool: 'c'});
  });

  testWidgets('Ohne Wahl bleibt der Speicher unberührt (altes „immer '
      'bestätigen“ bleibt D)', (tester) async {
    final env = _env(const ToolPrefs(alwaysConfirm: {_tool}));
    await storeHttpTools(env, [
      testHttpTool(risk: RiskLevel.write, autoRun: true),
    ]);
    final c = await pumpHttpTools(tester, env);
    await _open(tester);
    expect(_head(tester), 'Details · Stufe D · geändert');
    await _save(tester);
    expect(c.read(toolPrefsProvider).alwaysConfirm, {_tool});
    expect(_levels(c), isEmpty);
  });

  testWidgets('Migration lockert nichts: altes „ohne Nachfrage“ ergibt C als '
      'Standard, ohne es D', (tester) async {
    final env = _env(const ToolPrefs());
    await storeHttpTools(env, [
      testHttpTool(risk: RiskLevel.write, autoRun: true),
    ]);
    await pumpHttpTools(tester, env);
    await _open(tester);
    expect(_head(tester), 'Details · Stufe C · Standard');
  });

  testWidgets('write ohne „ohne Nachfrage“ ist D, read ist C', (tester) async {
    final env = _env(const ToolPrefs());
    await storeHttpTools(env, [testHttpTool(risk: RiskLevel.write)]);
    await pumpHttpTools(tester, env);
    await _open(tester);
    expect(_head(tester), 'Details · Stufe D · Standard');
    _back(tester);
    await settle(tester);

    final get = _env(const ToolPrefs());
    await storeHttpTools(get, [testHttpTool(method: HttpMethod.get)]);
    await pumpHttpTools(tester, get);
    await _open(tester);
    expect(_head(tester), 'Details · Stufe C · Standard');
  });

  testWidgets('Kaputter Wert zeigt D, nie den Standard', (tester) async {
    final env = _env(const ToolPrefs(levels: {_tool: 'x'}));
    await storeHttpTools(env, [testHttpTool(method: HttpMethod.get)]);
    await pumpHttpTools(tester, env);
    await _open(tester);
    expect(_head(tester), 'Details · Stufe D · geändert');
  });

  testWidgets('Umbenennen nimmt die Stufe mit, Löschen entfernt sie', (
    tester,
  ) async {
    final env = _env(const ToolPrefs(levels: {_tool: 'a'}));
    await storeHttpTools(env, [testHttpTool(method: HttpMethod.get)]);
    final c = await pumpHttpTools(tester, env);
    await _open(tester);
    expect(_head(tester), 'Details · Stufe A · geändert');
    await enter(tester, 'name', 'licht2');
    expect(_head(tester, 'http__licht2'), 'Details · Stufe A · geändert');
    await _save(tester);
    expect(_levels(c), {'http__licht2': 'a'});

    await tester.tap(find.text('http__licht2'));
    await settle(tester);
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await settle(tester);
    await syncSettle(tester);
    expect(_levels(c), isEmpty);
  });
}
