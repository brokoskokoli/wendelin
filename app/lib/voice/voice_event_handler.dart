// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'voice_controller.dart';

/// Maps pipeline events to the UI state and the voice log.
extension _VoiceEventHandler on VoiceController {
  /// WP120: the time line of the request runs from the end of the speech.
  void _onStateTraced(VoiceState s) {
    final latency = ref.read(latencyTraceProvider);
    if (s == VoiceState.transcribing) latency.begin();
    if (s == VoiceState.idle || s == VoiceState.listening) {
      latency.finishSoon();
    }
    _onState(s);
  }

  void _onEvent(VoiceEvent e) {
    switch (e) {
      case VoiceListening(:final followUp):
        state = state.copyWith(
          clearHint: true,
          clearError: true,
          clearFollowUp: !followUp,
        );
      case VoiceFollowUpListening(:final window, :final until):
        state = state.copyWith(followUpUntil: until, followUpWindow: window);
        voiceLogPipelineEvent(e);
      case VoiceConversationEnded():
        state = state.copyWith(clearFollowUp: true);
        voiceLogPipelineEvent(e);
      case VoiceTranscribed(:final transcript):
        _language = transcript.language;
        ref.read(latencyTraceProvider).sttDone();
      case VoiceNothingUnderstood(:final reason):
        voiceLog('nothing-understood', {'reason': reason});
        state = state.copyWith(
          hint: VoiceTexts.of(_language).nothingUnderstood,
        );
      case VoiceError(:final during, :final error):
        voiceLog('voice-error', {'phase': during, 'error': errorCode(error)});
        state = state.copyWith(error: voiceErrorText(uiTexts(ref), error));
      case VoiceSpeaking(:final sentence):
        _answers.spoke(sentence);
        ref.read(latencyTraceProvider).sentenceToTts();
        // Source of what is heard: the answer (not the confirmation).
        voiceLog('speak', {'source': 'answer'});
      case VoiceCancelled(:final reason, :final during):
        ref.read(latencyTraceProvider).abort();
        voiceLog('voice-cancelled', {'reason': reason, 'phase': during});
        _onCancelled(reason, during);
      case VoiceBargeIn():
        voiceLogPipelineEvent(e); // barge-in
      case VoiceAgentEvent(:final event):
        ref.read(latencyTraceProvider).agentEvent(event);
    }
  }

  // „Abgebrochen“: stop word (meta line, overlay reacts to stopCount) or
  // a tap before the agent got the request (B5).
  void _onCancelled(VoiceCancelReason reason, VoiceState during) {
    final stop = reason == VoiceCancelReason.stopWord;
    final tap =
        reason == VoiceCancelReason.tap &&
        (during == VoiceState.listening || during == VoiceState.transcribing);
    _answers.cancelled();
    if (!stop && !tap) return;
    if (stop) _agent.addNotice(cancelledText);
    // Both: the overlay hides the old exchange and closes (setting).
    state = state.copyWith(stopCount: state.stopCount + 1, hint: cancelledText);
  }
}
