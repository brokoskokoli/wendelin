part of 'voice_pipeline.dart';

/// Recording one utterance, incl. the held microphone (WP146).
extension VoicePipelineRecord on VoicePipeline {
  /// Records one utterance. Recordings are serialized: a new one waits
  /// until the previous (e.g. just cancelled) one has stopped the
  /// microphone, and each only clears its own hooks.
  Future<Endpoint?> _listen(
    int gen,
    EndpointConfig limits, {
    Int16List? preRoll,
    bool preRollIsSpeech = false,
    int? wakeEnd,
    bool preRollRest = false,
    bool holdMic = false,
    bool tail = false,
  }) {
    final previous = _listening;
    final run = _listenAfter(
      previous,
      gen,
      limits,
      preRoll,
      preRollIsSpeech,
      wakeEnd,
      preRollRest,
      holdMic,
      tail,
    );
    _listening = run.then((_) {});
    return run;
  }

  Future<Endpoint?> _listenAfter(
    Future<void> previous,
    int gen,
    EndpointConfig limits,
    Int16List? preRoll,
    bool preRollIsSpeech,
    int? wakeEnd,
    bool preRollRest,
    bool holdMic,
    bool tail,
  ) async {
    final log = _listenLog.start(diagnostics, clock);
    await _awaitMicFree(previous);
    if (gen != _gen) return null;
    final endpointer = Endpointer(limits);
    final done = Completer<Endpoint?>();
    void end(Endpoint? e) {
      if (!done.isCompleted) done.complete(e);
    }

    void fail(Object error) {
      if (done.isCompleted) return;
      _emit(VoiceError(VoiceState.listening, error));
      end(null);
    }

    StreamSubscription<Int16List>? sub;
    var held = false;
    final guards = <Timer>[];
    final levels = _LevelLog(diagnostics);
    _endListening = end;
    _endpointer = endpointer;
    try {
      vad.reset();
      if (preRoll != null) {
        final early = _feedPreRollLogged(
          endpointer,
          preRoll,
          preRollIsSpeech,
          wakeEnd,
          preRollRest,
        );
        if (early != null) end(early);
        // "Only the wake word" may follow: the early opened microphone keeps
        // buffering, the next recording continues with what it heard.
        held = holdMic && early != null;
      }
      if (!done.isCompleted) {
        _micHeld = false;
        sub = _openMic(endpointer, limits, levels, guards, end, fail, done, (
          first,
        ) {
          log.opened();
          return tail ? _bridgeBargeTail(endpointer, first) : null;
        });
      }
    } on Object catch (error) {
      fail(error);
    }
    final result = await done.future;
    if (identical(_endpointer, endpointer)) {
      _endListening = null;
      _endpointer = null;
    }
    for (final g in guards) {
      g.cancel();
    }
    levels.flush();
    // Whatever happened: the barge-in recording does not outlive this one.
    if (tail) _endBargeTail();
    log.ended(result);
    await _stopOrHoldMic(held && sub == null);
    // Not awaited: for a finished stream `cancel` returns a shared root-zone
    // future, and there is nothing left to wait for.
    unawaited(sub?.cancel());
    return result;
  }

  /// Waits for the previous recording and the barge-in detector.
  Future<void> _awaitMicFree(Future<void> previous) async {
    await previous;
    // The barge-in detector shares the microphone: it must have released
    // it (stop is queued with the state change) before this recording
    // starts, else the device says "already running" (WP64).
    // A hanging detector must not block the recording for ever: after the
    // timeout we start anyway (a still busy microphone gives a clear error).
    await _barge.settled.timeout(
      VoicePipeline.bargeReleaseTimeout,
      onTimeout: () => diagnostics?.call('barge-wait-timeout'),
    );
  }

  /// Stops the microphone after a recording; also without a subscription an
  /// early opened microphone must close when the pre-roll decided (WP146).
  /// [hold] keeps it open for a possible re-listen.
  Future<void> _stopOrHoldMic(bool hold) async {
    try {
      if (hold && audio.isRunning) {
        _micHeld = true;
      } else if (audio.isRunning) {
        _micHeld = false;
        await audio.stop();
      }
    } on Object catch (error) {
      _emit(VoiceError(VoiceState.listening, error));
    }
  }

  /// Stops a microphone that was kept open for a re-listen (WP146).
  void _releaseHeldMic() {
    if (!_micHeld) return;
    _micHeld = false;
    unawaited(audio.stop());
  }
}
