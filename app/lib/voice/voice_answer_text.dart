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

  /// Undoes [callId]: stops a spoken answer at once, adds „Zurückgenommen.“
  /// and speaks it if the request came by voice (B9). Returns the text, or
  /// `null` if the undo failed.
  Future<String?> undo(String callId) async {
    if (_voiceRun || state.phase != VoiceState.idle) await cancel(.undo);
    final tts = _promptTts;
    _promptTts = null;
    if (tts != null) await tts.stop();
    final byVoice = _callByVoice[callId] ?? _lastByVoice;
    final language = byVoice ? _language : ref.read(languageProvider);
    if (!await _agent.undo(callId)) return null;
    final text = undoneText(language);
    _agent.addNotice(text);
    final components = _components;
    if (byVoice && components != null) {
      _promptTts = await components
          .textToSpeech(language)
          .catchError((Object _) => null);
      state = state.copyWith(phase: VoiceState.speaking);
      try {
        await sayBounded(
          _promptTts,
          text,
          language: language,
          timeout: VoiceController.promptTimeout,
          source: 'undo',
        );
      } finally {
        _promptTts = null;
        if (ref.mounted && state.phase == VoiceState.speaking) {
          state = state.copyWith(phase: VoiceState.idle);
        }
      }
    }
    return text;
  }
}
