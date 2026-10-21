part of 'voice_pipeline.dart';

/// Answers a request given as text (WP114).
extension VoicePipelineText on VoicePipeline {
  /// Answers [text] like a recognized request, without listening: the agent
  /// runs and the answer is spoken (the request that waited for the unlock).
  /// Returns `false` if a request is already running.
  bool answerText(String text, {String? language}) {
    if (_disposed || _state != VoiceState.idle) return false;
    final gen = ++_gen;
    _session = _answerOnly(gen, Transcript(text: text, language: language));
    return true;
  }

  Future<void> _answerOnly(int gen, Transcript transcript) async {
    _setState(VoiceState.thinking);
    await _answer(gen, transcript);
    _finish(gen);
  }
}
