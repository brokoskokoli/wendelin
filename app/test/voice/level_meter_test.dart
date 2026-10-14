import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/wake_settings.dart';
import 'package:wendelin/voice/level_meter.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

class _Inner implements AudioInput {
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  Stream<Int16List> start() {
    _running = true;
    return Stream.fromIterable([
      Int16List.fromList([5, 5, 5]),
      Int16List.fromList([5, 5, 5]),
    ]);
  }

  @override
  Future<void> stop() async => _running = false;
}

void main() {
  test(
    'muteNextStart zeroes the first samples of the next start only',
    () async {
      final meter = MeteredAudioInput(_Inner())..muteNextStart(4);

      final first = await meter.start().toList();
      expect(first.expand((f) => f), [0, 0, 0, 0, 5, 5]);

      final second = await meter.start().toList();
      expect(second.expand((f) => f), [5, 5, 5, 5, 5, 5]);
      await meter.dispose();
    },
  );

  test('mute length covers the tone plus 50 ms', () {
    expect(wakeToneMuteSamples, wakeToneSamples + 800);
    expect(wakeToneMuteSamples, 3200);
  });
}
