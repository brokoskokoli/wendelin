// Gerätetest (WP88): Aufgaben auf einer SAF-Liste (`tasks__add`,
// `tasks__list`, `tasks__complete`, Rückgängig) mit Skript-Provider und
// festem Datum (`e2eNow`, 12.03.2030); auf „Speichern“ tippt
// `tool/e2e_android.sh`.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/platform/saf_list_file_port.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'support/e2e.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const picker = DocumentPicker();
  final port = SafListFilePort();
  String? uri;

  setUpAll(() async {
    final name = 'wendelin-e2e-${DateTime.now().millisecondsSinceEpoch}.md';
    uri = await picker
        .create(name)
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () => fail('Dateiauswahl nicht bestätigt'),
        );
    expect(uri, isNotNull, reason: 'Dateiauswahl abgebrochen');
  });
  tearDownAll(() async {
    if (uri case final u?) await picker.release(u);
  });

  testWidgets('tasks__add, list, complete und Rückgängig auf der SAF-Datei', (
    tester,
  ) async {
    final u = uri!;
    await port.write(u, '# Aufgaben\n\n- [ ] Alt\n');
    final provider = FakeLlmProvider([
      ScriptedTurn.toolCalls([
        const ToolCallBlock(
          id: 't1',
          name: 'tasks__add',
          argumentsJson:
              '{"title":"Steuer","due":"2026-10-20T14:30","priority":"high"}',
        ),
      ]),
      ScriptedTurn.text('Steuer ist eingetragen.'),
      ScriptedTurn.toolCalls([
        const ToolCallBlock(
          id: 't2',
          name: 'tasks__list',
          argumentsJson: '{"filter":"all"}',
        ),
      ]),
      ScriptedTurn.text('Offen: Steuer.'),
      ScriptedTurn.toolCalls([
        const ToolCallBlock(
          id: 't3',
          name: 'tasks__complete',
          argumentsJson: '{"title":"Steuer"}',
        ),
      ]),
      ScriptedTurn.text('Steuer ist erledigt.'),
    ]);
    await E2eApp(
      clock: FixedClock(e2eNow),
      startup: StartupSettings(
        enabledIntegrations: const {'lists', 'tasks'},
        lists: [
          ListDefinition(
            id: 'aufgaben',
            name: 'Aufgaben',
            target: u,
            taskDefault: true,
          ),
        ],
      ),
      config: (_) => ProviderConfig(
        primary: ProviderTarget(
          profileId: 'skript',
          modelId: 'skript',
          provider: provider,
          privacy: PrivacyLevel.local,
        ),
        names: const {'skript': 'Skript'},
      ),
    ).pump(tester);

    const open =
        '# Aufgaben\n\n- [ ] Alt\n- [ ] Steuer ⏰ 14:30 ⏫ 📅 2026-10-20\n';
    await send(tester, 'Trag die Steuer am 20.10. um 14:30 mit hoher Prio ein');
    await pumpUntil(tester, find.text('Steuer ist eingetragen.'));
    expect(await port.read(u), open);

    await send(tester, 'Welche Aufgaben habe ich?');
    await pumpUntil(tester, find.text('Offen: Steuer.'));

    await send(tester, 'Hak die Steuer ab');
    await pumpUntil(tester, find.text('Steuer ist erledigt.'));
    expect(
      await port.read(u),
      '# Aufgaben\n\n- [ ] Alt\n- [x] Steuer ⏰ 14:30 ⏫ 📅 2026-10-20 ✅ 2030-03-12\n',
    );

    final undo = undoButton(tester);
    expect(undo, findsWidgets);
    await tester.tap(undo.last);
    await pumpUntil(tester, find.text(l10n(tester).toolResultUndone));
    expect(await port.read(u), open);
  });
}
