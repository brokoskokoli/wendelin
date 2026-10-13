import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/platform/screen_protection.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/privacy_screen.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart';

const _channel = MethodChannel(windowChannelName);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  testWidgets('„Bildschirminhalt schützen“: aus als Standard, Schalter setzt '
      'FLAG_SECURE und speichert', (tester) async {
    final env = TestEnv();
    setView(tester, const Size(390, 1400));
    await tester.pumpWidget(
      ProviderScope(
        overrides: env.overrides,
        retry: (_, _) => null,
        child: themed(const PrivacyScreen()),
      ),
    );
    await tester.pump();
    final c = ProviderScope.containerOf(
      tester.element(find.byType(PrivacyScreen)),
    );
    expect(c.read(secureScreenProvider), isFalse);
    await tester.tap(find.byType(WSwitch).first);
    await tester.pump();
    await tester.pump();
    expect(c.read(secureScreenProvider), isTrue);
    expect(await env.storage.settings.get(AppSettings.secureScreen), isTrue);
    expect(calls.single.method, 'setSecure');
    expect(calls.single.arguments, {'secure': true});
  });

  test('ohne Plattform-Kanal: kein Fehler', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    await const ScreenProtection().apply(secure: true);
  });
}
