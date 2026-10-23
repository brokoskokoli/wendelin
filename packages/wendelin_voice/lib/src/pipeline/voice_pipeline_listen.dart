part of 'voice_pipeline.dart';

/// Announcing the listening phase and the confidence gate (WP140).
extension VoicePipelineListen on VoicePipeline {
  void _announceListening(TriggerEvent? trigger, bool followUp) {
    _emit(
      VoiceListening(trigger: followUp ? null : trigger, followUp: followUp),
    );
    if (followUp) {
      _emit(
        VoiceFollowUpListening(
          window: config.followUpWindow,
          until: clock.now().add(config.followUpWindow),
        ),
      );
    }
  }

  /// The confidence gate; logs a rejection (only confidence and mode, never
  /// the text) and asks again where the gate says so.
  Future<SttGateAction> _applyGate(
    int gen,
    Transcript transcript,
    TriggerEvent? trigger,
    bool followUp,
  ) async {
    final gate = config.confidenceGate.decide(
      transcript.confidence,
      followUp: followUp,
      source: trigger?.source,
    );
    if (gate == SttGateAction.accept) return gate;
    diagnostics?.call(
      'stt-reject reason=low-conf conf=${transcript.confidence} '
      'mode=${followUp ? 'followup' : trigger?.source.name ?? 'none'}',
    );
    if (gate == SttGateAction.askAgain) {
      await _nothingUnderstood(gen, null, language: transcript.language);
    }
    return gate;
  }
}
