// WP160 Analyse: kommt die speaker-enroll-Zeile über voiceLog an?
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
      expect(lines.where((l) => l.contains('speaker-enroll')), isNotEmpty);
    },
  );
}
