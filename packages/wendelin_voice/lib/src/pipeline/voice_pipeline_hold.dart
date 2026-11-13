part of 'voice_pipeline.dart';

/// Push-to-talk: holding the listening open (WP192).
extension VoicePipelineHold on VoicePipeline {
  bool get _isHolding => _holdGen != null && _holdGen == _gen;

  /// Holds the listening open (push-to-talk held, WP192): silence end,
  /// no-speech and follow-up window do not expire until [release] (or
  /// [EndpointConfig.holdMaxDuration]). Applies to the listening that runs
  /// (also the follow-up window); no effect outside [VoiceState.listening].
  void hold() {
    if (_state != VoiceState.listening) return;
    _holdGen = _gen;
    _wasHeld = true;
    _endpointer?.hold();
  }

  /// Lifts a hold without ending the listening (the press went away without
  /// a release, e.g. the button was removed): normal endpointing applies from
  /// now on and the recording no longer counts as held. No effect without a
  /// hold.
  void unhold() {
    if (!_isHolding) return;
    _holdGen = null;
    _wasHeld = false;
    _releasePendingGen = null;
    _endpointer?.unhold();
  }

  /// Ends a hold and processes the whole recording as one utterance (like
  /// [finishListening]). No effect without a hold or when the listening is
  /// already over. Released before the microphone is open: the listening
  /// ends as soon as it starts (nothing recorded yet).
  void release() {
    if (!_isHolding) return;
    final end = _endListening;
    final endpointer = _endpointer;
    if (_state != VoiceState.listening) return;
    if (end == null || endpointer == null) {
      _releasePendingGen = _gen;
      return;
    }
    _holdGen = null;
    end(endpointer.release());
  }

  /// A [release] that came before the endpointer existed ends the listening
  /// now.
  void _applyPendingRelease(
    int gen,
    Endpointer endpointer,
    void Function(Endpoint?) end,
  ) {
    if (_releasePendingGen == gen && _holdGen == gen) end(endpointer.release());
  }

  /// The listening is over: a hold counts for this one only; reaching the
  /// hard limit is announced.
  void _endHold(int gen, Endpoint? result) {
    if (_holdGen == gen) _holdGen = null;
    if (_releasePendingGen == gen) _releasePendingGen = null;
    if (result?.reason == EndpointReason.holdMax) {
      _emit(const VoiceHoldLimitReached());
    }
  }

  /// The listening of [gen] runs with [endpointer]; a hold applies.
  void _attach(int gen, Endpointer endpointer, void Function(Endpoint?) end) {
    _endListening = end;
    _endpointer = endpointer;
    _wasHeld = _holdGen == gen;
    if (_wasHeld) endpointer.hold();
  }

  /// Each recording only clears its own hooks.
  void _detach(Endpointer endpointer) {
    if (!identical(_endpointer, endpointer)) return;
    _endListening = null;
    _endpointer = null;
  }
}
