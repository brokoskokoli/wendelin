import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/channel_memory_trim.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('trim vom Kanal kommt als Stufe an, anderes wird ignoriert', () async {
    const channel = MethodChannel(memoryChannelName);
    final source = ChannelMemoryTrim();
    final levels = <int>[];
    final sub = source.levels.listen(levels.add);
    addTearDown(sub.cancel);

    Future<void> push(String method, Object? args) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            memoryChannelName,
            channel.codec.encodeMethodCall(MethodCall(method, args)),
            (_) {},
          );
    }

    await push('trim', 15);
    await push('trim', 'x');
    await push('other', 40);
    await pumpEventQueue();
    expect(levels, [15]);
  });
}
