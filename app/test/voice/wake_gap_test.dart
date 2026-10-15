import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/voice_controller.dart';

void main() {
  test('wakeGapMs: Lücke zwischen letztem Dienst-Sample und erstem Sample', () {
    // Service chunk arrived at t=1000 (its audio ends there); the first
    // overlay frame (100 ms long) arrives at t=1350: it began at 1250.
    expect(
      wakeGapMs(firstFrameAtMs: 1350, frameSamples: 1600, lastSampleAtMs: 1000),
      250,
    );
  });
}
