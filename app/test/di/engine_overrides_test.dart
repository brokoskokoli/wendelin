import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin/bootstrap/run_app.dart';
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/platform/platform_ports.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

void main() {
  test('engineOverrides liefert genau die übergebenen Objekte', () async {
    final storage = WendelinStorage(NativeDatabase.memory());
    addTearDown(storage.close);
    const startup = StartupSettings(enabledIntegrations: {'lists'});
    const device = DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin');
    final container = ProviderContainer(
      overrides: engineOverrides(storage, startup, device),
    );
    addTearDown(container.dispose);
    expect(container.read(storageProvider), same(storage));
    expect(container.read(startupProvider), same(startup));
    expect(container.read(deviceInfoProvider), same(device));
  });

  group('IntegrationDeps.extra', () {
    IntegrationDeps deps(Map<String, Object?> extras) => IntegrationDeps(
      ports: PlatformPorts(
        calendar: FakeCalendarPort(),
        clipboard: FakeClipboardPort(),
        alarms: FakeAlarmPort(),
        memory: FakeMemoryStore(),
        apps: FakeAppPresencePort(),
      ),
      device: const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
      httpClient: http.Client(),
      extras: extras,
    );

    test('fehlender Eintrag liefert null, passender den Wert', () {
      final d = deps({'a': 'x'});
      expect(d.extra<String>('b'), isNull);
      expect(d.extra<String>('a'), 'x');
      expect(deps({'n': null}).extra<String>('n'), isNull);
    });

    test('falscher Typ wirft StateError mit ID und Typ', () {
      expect(
        () => deps({'a': 1}).extra<String>('a'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains("'a'"), contains('String')),
          ),
        ),
      );
    });
  });
}
