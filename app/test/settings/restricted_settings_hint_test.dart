import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/restricted_settings_platform.dart';
import 'package:wendelin/ui/settings/restricted_settings_hint.dart';

import '../support/fake_restricted_settings.dart';
import '../support/test_env.dart';
import 'integrations_screen_test.dart' show pumpIntegrations, settle;

const _blocked = RestrictedSettings(
  opMode: RestrictedOpMode.ignored,
  installSource: InstallSource.file,
);
const _refused = RestrictedSettings(
  opMode: RestrictedOpMode.defaultMode,
  installSource: InstallSource.session,
);

Finder get _hint => find.byType(RestrictedSettingsHint);
Finder get _title => find.text('Android sperrt diese Freigabe');
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

void main() {
  group('WP159: SMS (Kontakte)', () {
    void noSms(TestEnv e) => e.phone.smsAllowed = false;

    testWidgets('gesperrt: Hinweis und Knopf öffnet die App-Infos', (
      tester,
    ) async {
      final fake = await _pump(tester, 'contacts', _blocked, setUp: noSms);
      expect(_title, findsOneWidget);
      expect(find.textContaining('die SMS-Berechtigung'), findsOneWidget);
      await tester.tap(_button);
      expect(fake.appInfoOpened, 1);
    });

    testWidgets('normale Ablehnung: kein Hinweis', (tester) async {
      await _pump(tester, 'contacts', _refused, setUp: noSms);
      expect(_title, findsNothing);
    });

    testWidgets('erteilt (auch bei Op ignored): kein Hinweis', (tester) async {
      await _pump(tester, 'contacts', _blocked, setUp: (_) {});
      expect(_title, findsNothing);
    });

    testWidgets('Op wird erst nach dem ersten Versuch gesetzt: Hinweis beim '
        'Zurückkehren in die App', (tester) async {
      final fake = FakeRestrictedSettingsPlatform()..current = _refused;
      final env = TestEnv(
        enabled: const {},
        extraOverrides: [
          restrictedSettingsPlatformProvider.overrideWithValue(fake),
        ],
      )..phone.smsAllowed = false;
      // Allein, ohne Registry-Änderungen: nur der Wechsel in den Vordergrund
      // löst die neue Abfrage aus.
      await tester.pumpWidget(
        env.app(
          home: const Scaffold(
            body: RestrictedSettingsHint(RestrictedFeature.sms),
          ),
        ),
      );
      await settle(tester);
      expect(_title, findsNothing);
      fake.current = _blocked;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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
        find.textContaining('den Benachrichtigungszugriff'),
        findsOneWidget,
      );
      await tester.tap(_button);
      expect(fake.appInfoOpened, 1);
    });

    testWidgets('normale Ablehnung: kein Hinweis', (tester) async {
      await _pump(tester, 'media', _refused, setUp: noAccess);
      expect(_title, findsNothing);
    });

    testWidgets('aktiv (auch bei Op ignored): kein Hinweis', (tester) async {
      await _pump(tester, 'media', _blocked, setUp: (_) {});
      expect(_title, findsNothing);
    });

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
