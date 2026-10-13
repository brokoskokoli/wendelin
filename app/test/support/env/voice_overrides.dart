import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wendelin/di/voice_providers.dart';

import '../test_env.dart';

/// Overrides of the voice pipeline: speech models, microphone and both
/// speech outputs.
List<Override> withVoice(TestEnv env) => [
  speechModelServiceProvider.overrideWith((ref) async => env.speechModels),
  microphoneProvider.overrideWithValue(env.microphone),
  systemTtsProvider.overrideWithValue(env.systemTts),
  sherpaTtsProvider.overrideWithValue(env.sherpaTts),
];
