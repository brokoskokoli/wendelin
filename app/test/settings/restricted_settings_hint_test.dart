import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/l10n/l10n.dart';
import 'package:wendelin/platform/restricted_settings_platform.dart';
import 'package:wendelin/ui/settings/restricted_settings_hint.dart';

import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../support/fake_restricted_settings.dart';
import '../support/test_env.dart';
import 'integrations_screen_test.dart' show pumpIntegrations, settle;

const _blocked = RestrictedSettings(installSource: InstallSource.file);
const _refused = RestrictedSettings(installSource: InstallSource.session);
const _unknownSource = RestrictedSettings();

Finder get _hint => find.byType(RestrictedSettingsHint);
Finder get _title => find.text('Freigabe fehlt, evtl. von Android gesperrt');
Finder get _button => find.text('App-Infos öffnen');

Future<FakeRestrictedSettingsPlatform> _pump(
  WidgetTester tester,
  String integration,
  RestrictedSettings state, {
  required void Function(TestEnv env) setUp,
}) async {
  final fake = FakeRestrictedSettingsPlatform()..current = state;
  final env = TestEnv(
    enabled: {integration},
    extraOverrides: [
      restrictedSettingsPlatformProvider.overrideWithValue(fake),
    ],
  );
  setUp(env);
  await pumpIntegrations(tester, env);
  await settle(tester);
  return fake;
}

Future<FakeRestrictedSettingsPlatform> _pumpAlone(
  WidgetTester tester,
  RestrictedFeature feature,
) async {
  final fake = FakeRestrictedSettingsPlatform()..current = _refused;
  final env = TestEnv(
    enabled: const {},
    extraOverrides: [
      restrictedSettingsPlatformProvider.overrideWithValue(fake),
    ],
  )..phone.smsAllowed = false;
  env.media.access = false;
  // Not WendelinApp: its start gate adds its own resume refresh of the
  // registry, which would hide the hint's own resume handler.
  await tester.pumpWidget(
    ProviderScope(
      overrides: env.overrides,
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: wendelinLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: RestrictedSettingsHint(feature)),
      ),
    ),
  );
  await settle(tester);
  // Wait until the start-up events of the app are through: afterwards only
  // the test triggers a new query.
  var seen = -1;
  while (fake.stateCalls != seen) {
    seen = fake.stateCalls;
    await settle(tester);
  }
  return fake;
}

ToolRegistry _registry(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(RestrictedSettingsHint)),
).read(toolRegistryProvider);

void main() {
  group('WP159: SMS (Kontakte)', () {
    void noSms(TestEnv e) => e.phone.smsAllowed = false;

    testWidgets('gesperrt: Hinweis und Knopf öffnet die App-Infos', (
      tester,
    ) async {
      final fake = await _pump(tester, 'contacts', _blocked, setUp: noSms);
      expect(_title, findsOneWidget);
      expect(find.textContaining('Die SMS-Berechtigung'), findsOneWidget);
      await tester.tap(_button);
      expect(fake.appInfoOpened, 1);
    });

    testWidgets('Installation per Sitzung/adb, SMS fehlt: kein Hinweis', (
      tester,
    ) async {
      await _pump(tester, 'contacts', _refused, setUp: noSms);
      expect(_title, findsNothing);
    });

    testWidgets('unbekannte Quelle, SMS fehlt: kein Hinweis', (tester) async {
      await _pump(tester, 'contacts', _unknownSource, setUp: noSms);
      expect(_title, findsNothing);
    });

    testWidgets('Datei-Installation, SMS erteilt: kein Hinweis', (
      tester,
    ) async {
      await _pump(tester, 'contacts', _blocked, setUp: (_) {});
      expect(_title, findsNothing);
    });

    testWidgets('Hinweis verschwindet, sobald SMS erteilt ist', (tester) async {
      late TestEnv env;
      await _pump(
        tester,
        'contacts',
        _blocked,
        setUp: (e) {
          env = e;
          noSms(e);
        },
      );
      expect(_title, findsOneWidget);
      env.phone.smsAllowed = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(_title, findsNothing);
    });

    testWidgets('Quelle ändert sich ohne Registry-Ereignis: Hinweis erst beim '
        'Zurückkehren in die App (nur Resume löst aus)', (tester) async {
      final fake = await _pumpAlone(tester, RestrictedFeature.sms);
      expect(_title, findsNothing);
      fake.current = _blocked;
      await settle(tester);
      expect(_title, findsNothing, reason: 'ohne Ereignis keine Abfrage');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(_title, findsOneWidget);
    });

    testWidgets('Registry-Ereignis nach der Anfrage: Hinweis ohne Resume '
        '(die Anfrage ändert die Registry)', (tester) async {
      final fake = await _pumpAlone(tester, RestrictedFeature.sms);
      fake.current = _blocked;
      _registry(tester).sensitiveMinimum = PrivacyLevel.tee;
      await settle(tester);
      expect(_title, findsOneWidget);
    });
  });

  group('WP159: Benachrichtigungszugriff (Medien)', () {
    void noAccess(TestEnv e) => e.media.access = false;

    testWidgets('gesperrt: Hinweis und Knopf öffnet die App-Infos', (
      tester,
    ) async {
      final fake = await _pump(tester, 'media', _blocked, setUp: noAccess);
      expect(_title, findsOneWidget);
      expect(
        find.textContaining('Der Benachrichtigungszugriff'),
        findsOneWidget,
      );
      await tester.tap(_button);
      expect(fake.appInfoOpened, 1);
    });

    testWidgets('Installation per Sitzung/adb, Zugriff fehlt: kein Hinweis', (
      tester,
    ) async {
      await _pump(tester, 'media', _refused, setUp: noAccess);
      expect(_title, findsNothing);
    });

    testWidgets('unbekannte Quelle, Zugriff fehlt: kein Hinweis', (
      tester,
    ) async {
      await _pump(tester, 'media', _unknownSource, setUp: noAccess);
      expect(_title, findsNothing);
    });

    testWidgets('Datei-Installation, Zugriff erteilt: kein Hinweis', (
      tester,
    ) async {
      await _pump(tester, 'media', _blocked, setUp: (_) {});
      expect(_title, findsNothing);
    });

    testWidgets('Hinweis verschwindet, sobald der Zugriff erteilt ist'
        '', (tester) async {
      late TestEnv env;
      await _pump(
        tester,
        'media',
        _blocked,
        setUp: (e) {
          env = e;
          noAccess(e);
        },
      );
      expect(_title, findsOneWidget);
      env.media.access = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(_title, findsNothing);
    });

    testWidgets(
      'Medien eingeschaltet, Quelle wird erst danach bekannt (Tipp in den '
      'Android-Einstellungen): nur Resume zeigt den Hinweis',
      (tester) async {
        final fake = await _pumpAlone(
          tester,
          RestrictedFeature.notificationAccess,
        );
        _registry(tester).sensitiveMinimum = PrivacyLevel.tee;
        await settle(tester);
        expect(_title, findsNothing);
        fake.current = _blocked;
        await settle(tester);
        expect(_title, findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle(tester);
        expect(_title, findsOneWidget);
      },
    );

    testWidgets('ausgeschaltete Integration: kein Hinweis', (tester) async {
      final fake = FakeRestrictedSettingsPlatform()..current = _blocked;
      final env = TestEnv(
        enabled: const {},
        extraOverrides: [
          restrictedSettingsPlatformProvider.overrideWithValue(fake),
        ],
      )..media.access = false;
      await pumpIntegrations(tester, env);
      await settle(tester);
      expect(_hint, findsNothing);
    });
  });
}
