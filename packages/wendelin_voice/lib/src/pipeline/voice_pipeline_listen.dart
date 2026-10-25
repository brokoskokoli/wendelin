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

  /// The pre-roll after the first segment of "only the wake word": the rest
  /// that is fed next, or null when it is used up (WP146).
  Int16List? _preRollLeft(Int16List? pre, int? wakeEnd, Duration elapsed) {
    final usedUp = (wakeEnd ?? 0) + durationToSamples(elapsed);
    final left = pre == null || usedUp >= pre.length
        ? null
        : Int16List.sublistView(pre, usedUp);
    diagnostics?.call(
      'relisten reason=wake-only preLeftMs='
      '${left == null ? 0 : samplesToDuration(left.length).inMilliseconds}',
    );
    return left;
  }

  /// Feeds the pre-roll; the decision may fall inside it (WP146), then the
  /// microphone is not needed at all. Logs numbers only.
  Endpoint? _feedPreRollLogged(
    Endpointer endpointer,
    Int16List preRoll,
    bool isSpeech,
    int? wakeEnd,
    bool rest,
  ) {
    final early = _feedPreRoll(
      endpointer,
      preRoll,
      isSpeech,
      wakeEnd,
      margin: !rest,
    );
    diagnostics?.call(
      'preroll-fed ms=${samplesToDuration(preRoll.length).inMilliseconds} '
      'from=${samplesToDuration(wakeEnd ?? 0).inMilliseconds} '
      'rest=$rest early=${early != null}',
    );
    return early;
  }

  /// Starts the microphone and the safety nets (wall-clock time in case the
  /// microphone stops delivering frames: before speech after the no-speech
  /// timeout, otherwise after the maximum duration, each plus a grace
  /// period); the timers go into [guards].
  StreamSubscription<Int16List> _openMic(
    Endpointer endpointer,
    EndpointConfig limits,
    _LevelLog levels,
    List<Timer> guards,
    void Function(Endpoint?) end,
    void Function(Object) fail,
    Completer<Endpoint?> done,
  ) {
    final sub = audio.start().listen(
      (frame) {
        if (done.isCompleted || frame.isEmpty) return;
        levels.add(frame);
        try {
          final e = endpointer.add(frame, speech: vad.isSpeech(frame));
          if (e != null) end(e);
        } on Object catch (error) {
          fail(error);
        }
      },
      onError: fail,
      onDone: () => end(endpointer.finish()),
    );
    guards
      ..add(
        Timer(limits.noSpeechTimeout + config.listenGrace, () {
          if (!endpointer.inSpeech) {
            end(endpointer.finish(EndpointReason.noSpeech));
          }
        }),
      )
      ..add(
        Timer(
          limits.maxDuration + config.listenGrace,
          () => end(endpointer.finish(EndpointReason.maxDuration)),
        ),
      );
    return sub;
  }

  /// Feeds the audio before the trigger in chunks of 30 ms. Without
  /// [wakeEnd] all of it counts as [isSpeech]. With it (wake word, WP68) the
  /// wake word itself is skipped, a short margin counts as silence and
  /// everything after it goes through the VAD: the request may already be
  /// in it, and the end-of-speech silence only counts from there.
  ///
  /// Returns the decision if it already falls inside the pre-roll.
  Endpoint? _feedPreRoll(
    Endpointer endpointer,
    Int16List preRoll,
    bool isSpeech,
    int? wakeEnd, {
    bool margin = true,
  }) {
    const chunk = 480;
    final from = wakeEnd == null ? 0 : wakeEnd.clamp(0, preRoll.length);
    final marginEnd =
        from + (margin ? durationToSamples(VoicePipeline.wakeEndMargin) : 0);
    for (var i = from; i < preRoll.length; i += chunk) {
      final end = i + chunk < preRoll.length ? i + chunk : preRoll.length;
      final frame = Int16List.sublistView(preRoll, i, end);
      final speech = wakeEnd == null
          ? isSpeech
          : i >= marginEnd && frame.length == chunk && vad.isSpeech(frame);
      final e = endpointer.add(frame, speech: speech);
      if (e != null) return e;
    }
    return null;
  }
}

/// Level statistics of one recording for the log (WP146): per second RMS and
/// peak in dBFS and the share of digital silence (all-zero samples), numbers
/// only. Tells a muted or doubled microphone from a bad recognition.
final class _LevelLog {
  _LevelLog(this._log);

  final void Function(String event)? _log;
  int _n = 0;
  int _zero = 0;
  int _peak = 0;
  double _sum = 0;
  int _second = 0;

  void add(Int16List frame) {
    if (_log == null) return;
    for (final s in frame) {
      final a = s < 0 ? -s : s;
      if (a == 0) _zero++;
      if (a > _peak) _peak = a;
      _sum += s * s;
    }
    _n += frame.length;
    if (_n >= 16000) _emit();
  }

  /// Writes the rest (less than a second) once at the end.
  void flush() {
    if (_n >= 1600) _emit();
    _n = 0;
  }

  void _emit() {
    final rms = math.sqrt(_sum / _n);
    _log?.call(
      'mic-level s=${_second++} rms=${_db(rms)} peak=${_db(_peak.toDouble())} '
      'zero=${(100 * _zero / _n).round()}',
    );
    _n = 0;
    _zero = 0;
    _peak = 0;
    _sum = 0;
  }

  static int _db(double v) =>
      v < 1 ? -99 : (20 * math.log(v / 32768) / math.ln10).round();
}
