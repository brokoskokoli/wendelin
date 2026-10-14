import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/channel_torch_port.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Stands in for `TorchChannel.kt`: a flash LED (or none), the torch state
/// and optional errors.
final class _FakeTorchChannel {
  bool hasLed = true;
  bool on = false;
  String? errorCode;
  final List<MethodCall> calls = [];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'isAvailable':
        return hasLed;
      case 'state':
        return on;
      case 'set':
        if (!hasLed) throw PlatformException(code: 'no_led');
        if (errorCode case final code?) throw PlatformException(code: code);
        on = (call.arguments as Map<Object?, Object?>)['on']! as bool;
        return null;
    }
    throw MissingPluginException();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(torchChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _FakeTorchChannel platform;

  setUp(() {
    platform = _FakeTorchChannel();
    messenger.setMockMethodCallHandler(channel, platform.handle);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  torchPortContract(() => const ChannelTorchPort(), name: 'ChannelTorchPort');
  torchPortContract(() {
    platform.hasLed = false;
    return const ChannelTorchPort();
  }, name: 'ChannelTorchPort ohne LED');

  test('set schickt on an den Kanal; state folgt der Systemkachel', () async {
    const port = ChannelTorchPort();
    await port.set(true);
    expect(platform.calls.single.method, 'set');
    expect(platform.calls.single.arguments, {'on': true});
    platform.on = false; // Systemkachel
    expect(await port.state(), isFalse);
  });

  test('Fehlercodes werden PortException', () async {
    const port = ChannelTorchPort();
    for (final (code, kind) in [
      ('camera_in_use', PortErrorKind.unavailable),
      ('unavailable', PortErrorKind.unavailable),
      ('no_led', PortErrorKind.unsupported),
    ]) {
      platform.errorCode = code;
      await expectLater(
        port.set(true),
        throwsA(isA<PortException>().having((e) => e.kind, 'kind', kind)),
      );
    }
  });

  test('ohne Kanal-Handler: unsupported', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      const ChannelTorchPort().set(true),
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
