// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'voice_controller.dart';

/// Maps pipeline events to the UI state and the voice log.
extension _VoiceEventHandler on VoiceController {
  void _onEvent(VoiceEvent e) {
    switch (e) {
      case VoiceListening():
        state = state.copyWith(clearHint: true, clearError: true);
      case VoiceTranscribed(:final transcript):
        _language = transcript.language;
      case VoiceNothingUnderstood(:final reason):
        voiceLog('nothing-understood', {'reason': reason});
        state = state.copyWith(
          hint: VoiceTexts.of(_language).nothingUnderstood,
        );
      case VoiceError(:final during, :final error):
        voiceLog('voice-error', {'phase': during, 'error': errorCode(error)});
        state = state.copyWith(error: voiceErrorText(error));
      case VoiceSpeaking():
        // Source of what is heard: the answer (not the confirmation).
        voiceLog('speak', {'source': 'answer'});
      case VoiceCancelled(:final reason, :final during):
        voiceLog('voice-cancelled', {'reason': reason, 'phase': during});
        _onCancelled(reason, during);
      case VoiceAgentEvent():
      case VoiceFollowUpListening():
      case VoiceBargeIn():
      case VoiceConversationEnded():
        voiceLogPipelineEvent(e); // agent, follow-up window, barge-in, exit
    }
  }

  // „Abgebrochen“: stop word (meta line, overlay reacts to stopCount) or
  // a tap before the agent got the request (B5).
  void _onCancelled(VoiceCancelReason reason, VoiceState during) {
    final stop = reason == VoiceCancelReason.stopWord;
    final tap =
        reason == VoiceCancelReason.tap &&
        (during == VoiceState.listening || during == VoiceState.transcribing);
    if (!stop && !tap) return;
    if (stop) _agent.addNotice(cancelledText);
    // Both: the overlay hides the old exchange and closes (setting).
    state = state.copyWith(stopCount: state.stopCount + 1, hint: cancelledText);
  }
}
