// Gerätetest (WP11): Listen über den echten SAF-Kanal (`FilesChannel.kt`).
//
// Die Datei legt die Android-Dateiauswahl an (`ACTION_CREATE_DOCUMENT`,
// persistente URI-Berechtigung); auf „Speichern“ tippt
// `tool/e2e_android.sh` per uiautomator. Danach laufen Lesen/Schreiben über
// `SafListFilePort` und `lists__add_items`/`lists__complete_item` über die
// App mit einem Skript-Provider.

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
          onTimeout: () => fail(
            'Dateiauswahl nicht bestätigt (tool/e2e_android.sh tippt auf '
            '„Speichern“)',
          ),
        );
    expect(uri, isNotNull, reason: 'Dateiauswahl abgebrochen');
  });
  tearDownAll(() async {
    if (uri case final u?) await picker.release(u);
  });

  testWidgets('SAF: Berechtigung, Name, Schreiben und Lesen byte-genau', (
    tester,
  ) async {
    final u = uri!;
    expect(u, startsWith('content://'));
    expect(await picker.hasAccess(u), isTrue, reason: 'persistente Freigabe');
    expect(await picker.displayName(u), endsWith('.md'));
    expect(await port.exists(u), isTrue);

    const crlf = '﻿# Test\r\n\r\n- [ ] Ä Ö Ü ß\r\n- [x] erledigt';
    await port.write(u, crlf);
    expect(await port.read(u), crlf, reason: 'BOM, CRLF, kein Schluss-\\n');

    const content = '# Einkaufen\n\n- [ ] Brot\n';
    await port.write(u, content);
    expect(
      await port.read(u),
      content,
      reason: 'Modus „wt“: kürzerer Inhalt ohne Rest des alten',
    );

    // Ohne Freigabe (fremde URI) ist das ein Fehler, nie stilles „false“
    // (ADR 0005 §4: verlorener Zugriff ≠ „gibt es nicht“).
    await expectLater(
      port.exists('$u-ohne-freigabe'),
      throwsA(
        isA<PortException>().having(
          (e) => e.kind,
          'kind',
          PortErrorKind.permissionDenied,
        ),
      ),
    );
  });

  testWidgets('lists__add_items und lists__complete_item auf der SAF-Datei', (
    tester,
  ) async {
    final u = uri!;
    await port.write(u, '# Einkaufen\n\n- [ ] Brot\n');
    final provider = FakeLlmProvider([
      ScriptedTurn.toolCalls([
        const ToolCallBlock(
          id: 'l1',
          name: 'lists__add_items',
          argumentsJson: '{"list":"Einkaufsliste","items":["Milch"]}',
        ),
      ]),
      ScriptedTurn.text('Milch steht auf der Liste.'),
      ScriptedTurn.toolCalls([
        const ToolCallBlock(
          id: 'l2',
          name: 'lists__complete_item',
          argumentsJson: '{"list":"Einkaufen","item":"Brot"}',
        ),
      ]),
      ScriptedTurn.text('Brot ist abgehakt.'),
    ]);
    await E2eApp(
      startup: StartupSettings(
        enabledIntegrations: const {'lists'},
        lists: [
          ListDefinition(
            id: 'einkaufen',
            name: 'Einkaufen',
            aliases: const ['Einkaufsliste'],
            target: u,
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

    await send(tester, 'Setz Milch auf die Einkaufsliste');
    await pumpUntil(tester, find.text('Milch steht auf der Liste.'));
    expect(await port.read(u), '# Einkaufen\n\n- [ ] Brot\n- [ ] Milch\n');

    await send(tester, 'Hak Brot ab');
    await pumpUntil(tester, find.text('Brot ist abgehakt.'));
    expect(await port.read(u), '# Einkaufen\n\n- [x] Brot\n- [ ] Milch\n');
  });
}
