@Tags(['live'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

// Live-Test gegen die eigene Home-Assistant-Instanz:
//   set -a; . ~/.wendelin-live.env; set +a; dart test -t live --run-skipped \
//     test/home_assistant/ha_live_test.dart
// Nur mit HA_URL und HA_TOKEN (Long-Lived Token); Werte nie ausgeben.
// Liest Version, Zustände und Räume. Mit HA_TEST_SWITCH (z. B.
// `switch.teststeckdose`) wird dieser Schalter einmal umgeschaltet und per
// Undo zurückgesetzt.

void main() {
  final url = Platform.environment['HA_URL'] ?? '';
  final token = Platform.environment['HA_TOKEN'] ?? '';
  final testSwitch = Platform.environment['HA_TEST_SWITCH'] ?? '';
  final skip = url.isEmpty || token.isEmpty
      ? 'HA_URL/HA_TOKEN nicht gesetzt'
      : null;

  late HttpHaApi api;
  setUp(() {
    api = HttpHaApi(
      FakeHaSecrets(HaEndpoint(url: HaUrl.parse(url), token: token)),
    );
  });
  tearDown(() => api.close());

  test('Version, Zustände, Räume', () async {
    expect(await api.check(), isNotEmpty);
    expect(await api.states(), isNotEmpty);
    expect(await api.entities(), isNotEmpty);
  }, skip: skip);

  test(
    'Schalter umschalten und per Undo zurück',
    () async {
      final before = (await api.state(testSwitch)).state;
      final ha = HaIntegration(
        api,
        FakeHaSecrets(),
        FakeHaEntityStore([
          HaEntity(entityId: testSwitch, name: 'Testschalter'),
        ]),
      );
      final o = await ha.tools.singleWhere((t) => t.name == 'ha__call').execute(
        {'entity': testSwitch, 'service': 'toggle'},
        _ctx(),
      );
      expect(o.isError, isFalse, reason: o.text);
      await o.undo!();
      expect((await api.state(testSwitch)).state, before);
    },
    skip: skip ?? (testSwitch.isEmpty ? 'HA_TEST_SWITCH nicht gesetzt' : null),
  );
}

ToolContext _ctx() => ToolContext(
  sessionId: 'live',
  clock: const SystemClock(),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);
