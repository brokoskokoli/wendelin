import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/flutter_clipboard_port.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Stands in for the platform clipboard (`SystemChannels.platform`).
final class _FakePlatformClipboard {
  String? text;
  bool failReads = false;
  bool failWrites = false;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'Clipboard.setData':
        if (failWrites) throw PlatformException(code: 'denied');
        text = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        return null;
      case 'Clipboard.getData':
        if (failReads) throw PlatformException(code: 'background');
        return text == null ? null : {'text': text};
      case 'Clipboard.hasStrings':
        return {'value': text?.isNotEmpty ?? false};
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakePlatformClipboard platform;

  setUp(() {
    platform = _FakePlatformClipboard();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, platform.handle);
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  clipboardPortContract(
    () => const FlutterClipboardPort(),
    name: 'FlutterClipboardPort',
  );

  test('Lesen im Hintergrund wird zu permissionDenied', () async {
    platform.failReads = true;
    await expectLater(
      const FlutterClipboardPort().read(),
      throwsA(
        isA<PortException>().having(
          (e) => e.kind,
          'kind',
          PortErrorKind.permissionDenied,
        ),
      ),
    );
  });

  test('Schreibfehler wird zu PortException(failed)', () async {
    platform.failWrites = true;
    await expectLater(
      const FlutterClipboardPort().write('x'),
      throwsA(
        isA<PortException>().having(
          (e) => e.kind,
          'kind',
          PortErrorKind.failed,
        ),
      ),
    );
  });

  test('schreibt über den Plattformkanal', () async {
    await const FlutterClipboardPort().write('Tauchen');
    expect(platform.text, 'Tauchen');
  });
}
