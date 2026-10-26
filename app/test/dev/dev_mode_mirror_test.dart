// WP148: Der Entwicklermodus erreicht den Wake-Dienst (Kotlin) ohne Neustart:
// Schalter und App-Start spiegeln das Flag über den Wake-Kanal.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/developer_mode.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/platform/wake/wake_platform.dart';

import '../support/test_env.dart';

final class _Recording extends WakePlatform {
  final modes = <bool>[];

  @override
  Future<void> setDevMode({required bool enabled}) async => modes.add(enabled);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'WakePlatform.setDevMode ruft devMode mit on auf dem Wake-Kanal',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(const MethodChannel(wakeChannelName), (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel(wakeChannelName),
          null,
        ),
      );
      await WakePlatform().setDevMode(enabled: true);
      await WakePlatform().setDevMode(enabled: false);
      expect([for (final c in calls) c.method], ['devMode', 'devMode']);
      expect(
        [for (final c in calls) (c.arguments as Map)['on']],
        [true, false],
      );
    },
  );

  test('ohne Plattform (Desktop, kein Dienst) kein Fehler', () async {
    await expectLater(WakePlatform().setDevMode(enabled: true), completes);
  });

  test('Schalter im Entwicklermodus spiegelt an Kotlin, an und aus', () async {
    final platform = _Recording();
    final c = TestEnv(
      extraOverrides: [wakePlatformProvider.overrideWithValue(platform)],
    ).container();
    addTearDown(c.dispose);
    await c.read(developerModeProvider.notifier).set(enabled: true);
    await c.read(developerModeProvider.notifier).set(enabled: false);
    expect(platform.modes, [true, false]);
  });
}
