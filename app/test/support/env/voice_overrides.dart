import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_settings.dart' show stopToneProvider;

import '../test_env.dart';

/// Overrides of the voice pipeline: speech models, microphone and both
/// speech outputs.
List<Override> withVoice(TestEnv env) => [
  speechModelServiceProvider.overrideWith((ref) async => env.speechModels),
  microphoneProvider.overrideWithValue(env.microphone),
  centralAudioBridgeProvider.overrideWithValue(env.centralAudioBridge),
  systemTtsProvider.overrideWithValue(env.systemTts),
  sherpaTtsProvider.overrideWithValue(env.sherpaTts),
  // WP195: no real audio output at a silent round (tests count it themselves).
  if (!env.realStopTone)
    stopToneProvider.overrideWithValue(env.stopTone ?? () async {}),
];
