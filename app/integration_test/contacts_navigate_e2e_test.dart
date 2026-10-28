// Gerätetest (WP164 C, E2E-Agent): contacts__navigate über den echten
// Kontakte-Kanal und die echte App-Erkennung, mit Fake-Launcher. Vorher legt
// der Host synthetische Kontakte an (Anna Meier mit einer Adresse, Clara Zell
// mit Privat/Arbeit, Bert Kurz nur mit Adresse) und erteilt READ_CONTACTS.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/platform/channel_app_presence_port.dart';
import 'package:wendelin/platform/channel_contacts_port.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

final class _RealPresenceApps implements NavigationApps {
  _RealPresenceApps(this.active, this.preferred);
  @override
  final Set<NavigationApp> active;
  @override
  final NavigationApp? preferred;
  final presence = const ChannelAppPresencePort();
  @override
  Future<bool> isInstalled(NavigationApp app) async =>
      // Google Maps is not on the AOSP emulator: count it as installed (the
      // launcher is a fake); Waze is asked for real.
      app == NavigationApp.googleMaps ||
      await presence.isInstalled(app.package);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final ctx = ToolContext(
    sessionId: 's',
    clock: FixedClock(DateTime.utc(2026, 10, 28, 12)),
    locale: 'de-DE',
    timeZone: 'Europe/Berlin',
  );
  String shown(ToolOutcome o) => '${o.text}|${o.summary}|${o.fixed?.params}';

  testWidgets('contacts__navigate: ok, Auswahl, kein Kontakt, Waze fehlt', (
    tester,
  ) async {
    final launcher = FakeMapsLauncherPort();
    final apps = _RealPresenceApps({
      NavigationApp.googleMaps,
      NavigationApp.waze,
    }, null);
    final nav = ContactsNavigateTool(
      ContactsFinder(const ChannelContactsPort()),
      NavigationStarter(launcher, apps),
    );
    final presence = const ChannelAppPresencePort();
    debugPrint(
      'E2E gmaps=${await presence.isInstalled('com.google.android.apps.maps')} '
      'waze=${await presence.isInstalled('com.waze')}',
    );

    final ok = await nav.execute({'name': 'Anna Meier'}, ctx);
    debugPrint('E2E ok: ${ok.text} | ${ok.summary} | fixed=${ok.fixed?.key}');
    expect(jsonDecode(ok.text), {'status': 'ok'});
    expect(launcher.launched, hasLength(1));
    debugPrint(
      'E2E launched: ${launcher.launched.single.package} '
      'uriHasAddress=${launcher.launched.single.uri.toString().contains('Musterstra')}',
    );
    expect(launcher.launched.single.uri.toString(), contains('Musterstra'));
    for (final s in ['Musterstra', '12345', 'Musterstadt']) {
      expect(shown(ok), isNot(contains(s)));
    }

    final only = await nav.execute({'name': 'Bert Kurz'}, ctx);
    expect(jsonDecode(only.text), {'status': 'ok'}, reason: only.text);
    expect(launcher.launched, hasLength(2));

    launcher.launched.clear();
    final choice = await nav.execute({'name': 'Clara Zell'}, ctx);
    debugPrint('E2E choice: ${choice.text}');
    final cj = jsonDecode(choice.text) as Map<String, Object?>;
    expect(cj['status'], 'choice_needed');
    expect(cj['address_labels'], hasLength(2));
    for (final s in ['straße', 'str.', '12345', '54321']) {
      expect(shown(choice).toLowerCase(), isNot(contains(s)));
    }
    expect(launcher.launched, isEmpty);
    final work = await nav.execute({
      'name': 'Clara Zell',
      'address_label': (cj['address_labels']! as List)[1],
    }, ctx);
    expect(jsonDecode(work.text), {'status': 'ok'}, reason: work.text);
    expect(
      launcher.launched.single.uri.toString(),
      isNot(contains('Musterstra')),
    );
    launcher.launched.clear();

    final none = await nav.execute({'name': 'Zacharias Unbekannt'}, ctx);
    expect(jsonDecode(none.text), {'status': 'no_contact'});
    expect(launcher.launched, isEmpty);

    // Waze is not installed on the emulator: clear message, no fallback.
    final waze = await nav.execute({'name': 'Anna Meier', 'app': 'waze'}, ctx);
    debugPrint('E2E waze: ${waze.text} | ${waze.summary}');
    expect(jsonDecode(waze.text), {'status': 'app_unavailable'});
    expect(launcher.launched, isEmpty);

    final pref = ContactsNavigateTool(
      ContactsFinder(const ChannelContactsPort()),
      NavigationStarter(
        launcher,
        _RealPresenceApps({
          NavigationApp.googleMaps,
          NavigationApp.waze,
        }, NavigationApp.waze),
      ),
    );
    final w2 = await pref.execute({'name': 'Anna Meier'}, ctx);
    debugPrint('E2E waze-pref: ${w2.text} | ${w2.summary}');
    expect(jsonDecode(w2.text), {'status': 'app_unavailable'});
    expect(launcher.launched, isEmpty);

    // maps__navigate with Waze: clear message, no fallback.
    final starter = NavigationStarter(launcher, apps);
    final r = await starter.resolve('waze');
    debugPrint('E2E resolve waze: app=${r.app} msg=${r.unavailable?.message}');
    expect(r.app, isNull);
    expect(r.unavailable!.message, contains('nicht installiert'));
  });
}
