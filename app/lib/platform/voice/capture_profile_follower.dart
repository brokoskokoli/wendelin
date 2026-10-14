import 'dart:async';

import 'package:wendelin_voice/wendelin_voice.dart';

import '../../voice/voice_log.dart';
import 'record_audio_input.dart';

/// Keeps the microphone source in step with the pipeline: only while the
/// answer is spoken (`VoiceState.speaking`) the next recording uses the
/// communication source with echo cancellation ([CaptureProfile.
/// speechOutput]); in every other state it is back to the recognition
/// source, so the request to Whisper never gets a worse source (K23 c).
final class CaptureProfileFollower {
  /// Follows [states] and sets the profile of [input].
  CaptureProfileFollower(this.input, Stream<VoiceState> states) {
    _sub = states.listen(_onState);
  }

  /// The microphone.
  final ProfiledAudioInput input;

  late final StreamSubscription<VoiceState> _sub;

  void _onState(VoiceState state) {
    final wanted = state == VoiceState.speaking
        ? CaptureProfile.speechOutput
        : CaptureProfile.recognition;
    if (input.profile == wanted) return;
    if (input.useProfile(wanted)) {
      voiceLog('audio-source', {'profile': wanted});
    }
  }

  /// Stops following; the input returns to the recognition source.
  Future<void> dispose() async {
    await _sub.cancel();
    input.useProfile(CaptureProfile.recognition);
  }
}
