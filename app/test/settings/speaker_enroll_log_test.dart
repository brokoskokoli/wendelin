// WP160: die speaker-enroll-Zeile kommt über voiceLog an, ohne Namen.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/speaker_providers.dart';
import 'package:wendelin/voice/voice_log.dart';

import 'speaker_screen_test.dart' show speakerEnv;

void main() {
  test(
    'Einlernen über den Provider schreibt speaker-enroll in voiceLog',
    () async {
      final lines = <String>[];
      final old = voiceLogSink;
      voiceLogSink = lines.add;
      addTearDown(() => voiceLogSink = old);
      final env = speakerEnv();
      final c = env.container();
      addTearDown(c.dispose);
      await c
          .read(speakerProfilesProvider.notifier)
          .enroll(
            name: 'Anna',
            samples: [for (var i = 0; i < 5; i++) Int16List(48000)],
          );
      expect(
        lines.where(
          (l) => l.startsWith('Wendelin/voice: speaker-enroll samples=5 '),
        ),
        hasLength(1),
      );
      expect(lines.any((l) => l.contains('speaker-enroll-failed')), isFalse);
      expect(lines.any((l) => l.contains('Anna')), isFalse);
    },
  );
}
