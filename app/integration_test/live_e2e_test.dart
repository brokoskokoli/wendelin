// Live-Gerätetest (WP11, manuell): „Trag mir morgen um 10 Tauchen ein“ mit
// Claude Haiku über die echte App auf dem Emulator in den Gerätekalender,
// danach Rückgängig.
//
// Nur mit `WENDELIN_LIVE=1 tool/e2e_android.sh integration_test/live_e2e_test.dart`
// und gesetztem ANTHROPIC_API_KEY. Das Skript schiebt den Key per
// `adb shell run-as` in die privaten App-Daten (nie auf die Platte des
// Rechners, nie in den Build); der Test liest und löscht die Datei sofort,
// der Key liegt danach nur im In-Memory-SecretStore. Nach dem Lauf löscht das
// Skript die App-Daten (`pm clear`).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/platform/device_calendar_port.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'support/e2e.dart';

const _live = bool.fromEnvironment('WENDELIN_LIVE');
const _model = 'claude-haiku-5-5';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final port = DeviceCalendarPort();

  testWidgets('Claude Haiku trägt „Tauchen“ in den Gerätekalender ein', (
    tester,
  ) async {
    await expectCalendarPermission(port);
    final key = await takeLiveKey();
    expect(key, isNotEmpty);
    final adapter = AnthropicMessagesAdapter(
      credentials: Credentials.apiKey(key, style: ApiKeyStyle.xApiKey),
      defaultModel: _model,
      options: const AnthropicOptions(reasoningEffort: 'low'),
    );
    final app = E2eApp(
      config: (_) => ProviderConfig(
        primary: ProviderTarget(
          profileId: 'claude',
          modelId: _model,
          provider: adapter,
          privacy: PrivacyLevel.standard,
        ),
        names: const {'claude': 'Claude Haiku'},
      ),
    );
    await app.pump(tester);
    final watch = Stopwatch()..start();
    await send(tester, 'Trag mir morgen um 10 Tauchen ein');
    await pumpUntil(
      tester,
      undoButton(tester),
      timeout: const Duration(seconds: 60),
    );
    await waitIdle(tester);
    watch.stop();

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final events = (await port.listEvents(
      TimeRange(tomorrow, tomorrow.add(const Duration(days: 1))),
    )).where((e) => e.title.toLowerCase().contains('tauch')).toList();
    expect(events, hasLength(1));
    final local = events.single.start.toLocal();
    expect((local.hour, local.minute), (10, 0));

    final undo = undoButton(tester);
    if (undo.evaluate().isNotEmpty) {
      await tester.tap(undo);
      await pumpUntil(tester, find.text(l10n(tester).toolResultUndone));
    } else {
      await port.deleteEvent(events.single.id); // Fenster abgelaufen
    }
    expect(await port.getEvent(events.single.id), isNull);

    final audit = await auditText(app);
    expect(audit, contains('calendar__create_event'));
    for (final line in audit.split('\n').where((l) => l.startsWith('usage'))) {
      // ignore: avoid_print
      print('Live-Emulator $line');
    }
    // ignore: avoid_print
    print('Live-Emulator: ${watch.elapsedMilliseconds} ms bis Antwort');
    expect(find.byType(ToolResultCard), findsOneWidget);
  }, skip: !_live);
}
