part of 'voice_controller.dart';

/// Answers a request given as text, aloud (WP114).
extension VoiceAnswerText on VoiceController {
  /// Answers [text] as if it was spoken: the agent runs and the answer is
  /// read aloud (the request that waited for the unlock). Returns `false`
  /// when speech is not available or busy; the caller then sends it as
  /// typed text.
  Future<bool> answerText(String text) async {
    // A follow-up listening ends as a restart (not as a user abort). So does
    // the „please unlock“ hint when it is still spoken (quick unlock): it is
    // cut off, so the answer follows aloud instead of going out as typed
    // text. A request that is working (recognition, agent) is left alone.
    final state = _pipeline?.state;
    if (state == VoiceState.listening || state == VoiceState.speaking) {
      await cancel(VoiceCancelReason.retrigger);
      // Defensive: after `cancel` the pipeline is idle already; this only
      // lets an old session run out (no test can make it late).
      await _pipeline?.whenIdle;
    }
    if (_pipeline != null && _pipeline!.state != VoiceState.idle) return false;
    final cancels = _cancels;
    final VoiceComponents? components;
    try {
      components = await _loadComponents();
    } on Object catch (e) {
      voiceLog('answer-text-failed', {'error': errorCode(e)});
      return false;
    }
    // Cancelled while the models loaded (home, close): nothing starts, and
    // `true` keeps the caller from sending the text as typed.
    if (cancels != _cancels) return true;
    return components != null && _pipelineFor(components).answerText(text);
  }
}
