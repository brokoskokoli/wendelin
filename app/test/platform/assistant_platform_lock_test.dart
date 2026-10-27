// WP158: an unreadable lock state counts as locked (fail-closed).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/voice/voice_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(assistantChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> logs;
  setUp(() {
    logs = [];
    voiceLogSink = logs.add;
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('PlatformException: gesperrt', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'boom'),
    );
    expect(await AssistantPlatform().isLocked(), isTrue);
    expect(logs.single, contains('lock-check-failed'));
    expect(logs.single, contains('reason=platform-error'));
  });

  test('keine Antwort (null): gesperrt', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await AssistantPlatform().isLocked(), isTrue);
    expect(logs.single, contains('reason=no-answer'));
  });

  test('ohne Plugin (MissingPluginException): gesperrt', () async {
    expect(await AssistantPlatform().isLocked(), isTrue);
    expect(logs.single, contains('reason=missing-plugin'));
  });

  test('echte Antworten bleiben unverändert', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    expect(await AssistantPlatform().isLocked(), isFalse);
    messenger.setMockMethodCallHandler(channel, (call) async => true);
    expect(await AssistantPlatform().isLocked(), isTrue);
    expect(logs, isEmpty);
  });
}
