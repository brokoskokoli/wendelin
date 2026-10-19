// WP85: Verdrahtung der Integration „contacts“ (Kontakte, SMS, Anruf).
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin/di/integrations/contacts_spec.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/sms_drafts.dart';
import 'package:wendelin/platform/platform_ports.dart';
import 'package:wendelin/voice/locked_agent_run.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart' show LockedCommand;

import '../support/test_env.dart';

void main() {
  test('Kontakte: Tools über die Ports, sensibel, nie bei Sperre', () async {
    final env = TestEnv(enabled: const {'contacts'});
    final c = env.container();
    addTearDown(c.dispose);
    final registry = c.read(toolRegistryProvider);
    await registry.refresh();
    expect(registry.status('contacts'), IntegrationStatus.active);
    expect(registry.info('contacts').integration.sensitive, isTrue);
    final catalog = registry.catalogFor(PrivacyLevel.local, sessionId: 's');
    final ctx = ToolContext(
      sessionId: 's',
      clock: FixedClock(testNow),
      locale: 'de-DE',
      timeZone: 'Europe/Berlin',
    );
    final found = await catalog.lookup('contacts__find')!.execute({
      'query': 'Anna',
    }, ctx);
    expect(found.text, contains('Anna Meier'));
    // Gleicher Entwurfsspeicher wie in der Oberfläche.
    final edits = c.read(smsDraftEditsProvider);
    edits.set('+491701234567', 'Hallo', 'Hallo Anna');
    final sent = await catalog.lookup('sms__compose')!.execute({
      'to': '+49 170 1234567',
      'text': 'Hallo',
    }, ctx);
    expect(sent.isError, isFalse, reason: sent.text);
    expect(env.phone.sent.single.text, 'Hallo Anna');
    await catalog.lookup('phone__call')!.execute({'to': '0171 111'}, ctx);
    expect(env.phone.called, ['0171111']);
    expect(contactsSpec.allowedWhileLocked, isFalse);
    // Das Sperr-Gate kennt nur die Taschenlampe als Befehl.
    expect(LockedCommand.values.map(lockedToolName).toSet(), {
      'flashlight__on',
      'flashlight__off',
    });
  });

  test('Kontakte: Berechtigung beim Einschalten, nicht vorher', () async {
    final env = TestEnv();
    var asked = 0;
    final deps = IntegrationDeps(
      ports: PlatformPorts(
        calendar: env.calendar,
        clipboard: env.clipboard,
        alarms: env.alarms,
        memory: env.memory,
        apps: env.apps,
        torch: env.torch,
        contacts: env.contacts,
        phone: env.phone,
        requestContactsPermission: () async {
          asked++;
          return true;
        },
      ),
      device: const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
      httpClient: http.Client(),
    );
    expect(contactsSpec.isSupported!(deps), isTrue);
    // Nichts fragt vorher: weder die Prüfung noch das Anlegen der Tools.
    expect(asked, 0);
    expect(await contactsSpec.requestPermission!(deps), isTrue);
    expect(asked, 1);
    // Ohne Ports (z. B. iOS) gibt es die Integration nicht.
    final bare = IntegrationDeps(
      ports: PlatformPorts(
        calendar: env.calendar,
        clipboard: env.clipboard,
        alarms: env.alarms,
        memory: env.memory,
        apps: env.apps,
        torch: env.torch,
      ),
      device: const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
      httpClient: http.Client(),
    );
    expect(contactsSpec.isSupported!(bare), isFalse);
  });
}
