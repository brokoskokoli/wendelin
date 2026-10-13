import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/channel_app_presence_port.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Stands in for `AppsChannel.kt`: answers like `PackageManager` on a
/// device with the [installed] packages (all declared in `<queries>`).
final class _FakeAppsChannel {
  Set<String> installed = {};
  final List<MethodCall> calls = [];
  PlatformException? failure;
  bool answerNull = false;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (failure case final f?) throw f;
    if (call.method != 'isInstalled') throw MissingPluginException();
    if (answerNull) return null;
    final pkg = (call.arguments as Map<Object?, Object?>)['package'];
    return installed.contains(pkg);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(appsChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _FakeAppsChannel platform;

  setUp(() {
    platform = _FakeAppsChannel();
    messenger.setMockMethodCallHandler(channel, platform.handle);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  appPresencePortContract((installed) {
    platform.installed = installed;
    return const ChannelAppPresencePort();
  }, name: 'ChannelAppPresencePort');

  test('fragt den Kanal mit dem Paketnamen', () async {
    platform.installed = {'md.obsidian'};
    expect(
      await const ChannelAppPresencePort().isInstalled('md.obsidian'),
      isTrue,
    );
    expect(platform.calls.single.method, 'isInstalled');
    expect(platform.calls.single.arguments, {'package': 'md.obsidian'});
  });

  test('ungültiger Name geht nicht an den Kanal', () async {
    await expectLater(
      const ChannelAppPresencePort().isInstalled('kein paket'),
      throwsArgumentError,
    );
    expect(platform.calls, isEmpty);
  });

  test('Kanalfehler wird PortException(failed)', () async {
    platform.failure = PlatformException(code: 'boom');
    await expectLater(
      const ChannelAppPresencePort().isInstalled('md.obsidian'),
      throwsA(
        isA<PortException>().having(
          (e) => e.kind,
          'kind',
          PortErrorKind.failed,
        ),
      ),
    );
  });

  test('keine Antwort wird PortException(failed), nicht „fehlt“', () async {
    platform.answerNull = true;
    await expectLater(
      const ChannelAppPresencePort().isInstalled('md.obsidian'),
      throwsA(
        isA<PortException>().having(
          (e) => e.kind,
          'kind',
          PortErrorKind.failed,
        ),
      ),
    );
  });

  test('ohne Plattformseite: PortException(unsupported)', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      const ChannelAppPresencePort().isInstalled('md.obsidian'),
      throwsA(
        isA<PortException>().having(
          (e) => e.kind,
          'kind',
          PortErrorKind.unsupported,
        ),
      ),
    );
  });
}
