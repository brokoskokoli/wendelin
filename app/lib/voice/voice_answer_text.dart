part of 'voice_controller.dart';

/// Answers a request given as text, aloud (WP114).
extension VoiceAnswerText on VoiceController {
  /// Answers [text] as if it was spoken: the agent runs and the answer is
  /// read aloud (the request that waited for the unlock). Returns `false`
  /// when speech is not available or busy; the caller then sends it as
  /// typed text.
  Future<bool> answerText(String text) async {
    if (_pipeline != null && _pipeline!.state != VoiceState.idle) return false;
    final VoiceComponents? components;
    try {
      components = await _loadComponents();
    } on Object catch (e) {
      voiceLog('answer-text-failed', {'error': errorCode(e)});
      return false;
    }
    return components != null && _pipelineFor(components).answerText(text);
  }
}
