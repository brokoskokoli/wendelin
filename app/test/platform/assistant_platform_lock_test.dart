// WP158: an unreadable lock state counts as locked (fail-closed).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/assistant_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(assistantChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('PlatformException: gesperrt', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'boom'),
    );
    expect(await AssistantPlatform().isLocked(), isTrue);
  });

  test('keine Antwort (null): gesperrt', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await AssistantPlatform().isLocked(), isTrue);
  });

  test('ohne Plugin (MissingPluginException): gesperrt', () async {
    expect(await AssistantPlatform().isLocked(), isTrue);
  });

  test('echte Antworten bleiben unverändert', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    expect(await AssistantPlatform().isLocked(), isFalse);
    messenger.setMockMethodCallHandler(channel, (call) async => true);
    expect(await AssistantPlatform().isLocked(), isTrue);
  });
}
