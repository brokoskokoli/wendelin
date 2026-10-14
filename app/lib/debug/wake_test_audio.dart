import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../platform/voice/wav_audio_input.dart';
import 'device_test_overrides.dart' show deviceTestFolder;

/// Debug builds only (WP50): the wake word service of a device test hears
/// a WAV instead of the microphone. The test writes
/// `files/e2e/wake.json` (`run-as`): `{"audio": "wake.wav",
/// "leadingSilence": 12}`, a 16 kHz mono file in `files/e2e/` and the
/// silence (seconds, default 0.3) before it. The WAV plays at every start of the listening,
/// i.e. again after each pause for the overlay. `null` in release builds,
/// without the file or for an invalid one.
Future<AudioInput?> debugWakeAudio({Directory? base}) async {
  if (!kDebugMode) return null;
  final dir = Directory(
    '${(base ?? await getApplicationSupportDirectory()).path}/'
    '$deviceTestFolder',
  );
  final file = File('${dir.path}/wake.json');
  if (!file.existsSync()) return null;
  try {
    final spec = jsonDecode(file.readAsStringSync());
    final name = spec is Map ? spec['audio'] : null;
    if (name is! String ||
        name.isEmpty ||
        name.contains('/') ||
        name.contains(r'\')) {
      throw const FormatException('audio: nur ein Dateiname');
    }
    final speed = spec is Map && spec['speed'] is num
        ? (spec['speed'] as num).toDouble()
        : 1.0;
    // The WAV waits [lead] seconds at every start, so a test can put the
    // device to sleep before the „Wendelin“ comes.
    final lead = spec is Map && spec['leadingSilence'] is num
        ? (spec['leadingSilence'] as num).toDouble()
        : 0.3;
    return WavAudioInput(
      WavAudioInput.file('${dir.path}/$name').samples,
      speed: speed,
      leadingSilence: Duration(milliseconds: (lead * 1000).round()),
    );
  } on Object catch (e) {
    debugPrint('Gerätetest: ${file.path} ungültig: $e');
    return null;
  }
}
