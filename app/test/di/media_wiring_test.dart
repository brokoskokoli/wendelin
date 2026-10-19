// WP90 (nach WP98 verlegt): Verdrahtung der Integration „media“. Eigene Datei,
// damit `wiring_test.dart` bei neuen Integrationen nicht konfliktiert.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin/di/integrations/media_spec.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../support/test_env.dart';

void main() {
  test('Medien: Tools über den Media-Port, Zugriff optional', () async {
    final env = TestEnv(enabled: const {'media'});
    env.media.snapshot = const MediaSnapshot(
      packageName: audiblePackage,
      appName: 'Audible',
      playing: true,
      title: 'Buch',
      positionMs: 60000,
    );
    final c = env.container();
    addTearDown(c.dispose);
    final registry = c.read(toolRegistryProvider);
    await registry.refresh();
    expect(registry.status('media'), IntegrationStatus.active);
    final catalog = registry.catalogFor(PrivacyLevel.local, sessionId: 's');
    final ctx = ToolContext(
      sessionId: 's',
      clock: FixedClock(testNow),
      locale: 'de-DE',
      timeZone: 'Europe/Berlin',
    );
    final o = await catalog.lookup('media__pause')!.execute({}, ctx);
    expect(o.isError, isFalse, reason: o.text);
    expect(env.media.sent, [MediaCommand.pause]);
    // Ohne Benachrichtigungszugriff: Integration bleibt aktiv (Schritt optional).
    env.media.access = false;
    await registry.refresh('media');
    expect(registry.status('media'), IntegrationStatus.active);
    expect(registry.info('media').setup.missingSteps, ['notification_access']);
    expect(mediaSpec.allowedWhileLocked, isFalse);
  });

  test(
    'Medien: Einschalten öffnet die Zugriffsseite, bei Zugriff nicht',
    () async {
      final env = TestEnv();
      final deps = IntegrationDeps(
        ports: env.ports,
        device: const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
        httpClient: http.Client(),
      );
      env.media.access = false;
      expect(await mediaSpec.requestPermission!(deps), isFalse);
      expect(env.media.settingsOpened, 1);
      env.media.access = true;
      expect(await mediaSpec.requestPermission!(deps), isTrue);
      expect(env.media.settingsOpened, 1);
      expect(mediaSpec.isSupported!(deps), isTrue);
    },
  );
}
