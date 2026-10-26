part of 'voice_pipeline.dart';

/// The longest hole between the barge-in tail and the first frame of the
/// follow-up microphone that is filled with silence (WP146); the opening
/// took ~0.5 s on the device, more than twice that is a measuring error.
const _bargeTailHoleMax = Duration(milliseconds: 1000);

/// Developer mode (WP148): receives events **with content** (recognized
/// and dropped texts). The app sets a function that writes nothing unless
/// the developer mode is on; `null` = none.
mixin VoiceContentLog {
  /// The receiver of events with content.
  void Function(String event, Map<String, Object?> fields)? contentLog;

  /// The receiver of the whole recordings of an interaction (`rec`): lead-in
  /// (wake word pre-roll or barge-in tail, with inserted silence) and the
  /// microphone; nothing is collected unless it is on.
  DevClips? devClips;
}

/// The whole recording of one listening (WP148): the audio in the order the
/// endpointer got it, with the places where the sources meet.
final class _DevRec {
  _DevRec() : at = DateTime.now();

  final DateTime at;
  final _parts = <Int16List>[];
  final marks = <String, int>{};
  int _len = 0;

  /// Offset of the endpointer's time 0 in the recording.
  int base = 0;

  void add(String? mark, Int16List pcm) {
    if (mark != null) marks[mark] = samplesToDuration(_len).inMilliseconds;
    if (pcm.isEmpty) return;
    _parts.add(pcm);
    _len += pcm.length;
  }

  DevClip? build(Endpoint? e) {
    if (_len == 0) return null;
    final out = Int16List(_len);
    var at0 = 0;
    for (final p in _parts) {
      out.setAll(at0, p);
      at0 += p.length;
    }
    final start = e?.speechStart;
    final end = e?.speechEnd;
    final b = samplesToDuration(base).inMilliseconds;
    return DevClip(
      event: 'rec',
      pcm: out,
      at: at,
      marksMs: {
        ...marks,
        if (start != null) 'speechStart': b + start.inMilliseconds,
        if (end != null) 'speechEnd': b + end.inMilliseconds,
        if (e != null) 'decided': b + e.elapsed.inMilliseconds,
      },
    );
  }
}

/// Announcing the listening phase and the confidence gate (WP140).
extension VoicePipelineListen on VoicePipeline {
  void _onTrigger(TriggerEvent e) {
    if (_state != VoiceState.idle) {
      unawaited(cancel(VoiceCancelReason.retrigger));
    }
    start(trigger: e);
  }

  void _abortActivities() {
    final end = _endListening;
    if (end != null) end(null);
    _releaseHeldMic();
    if (_agentRunning) agent.cancel();
    final q = _queue;
    _queue = null;
    if (q != null) unawaited(q.stop());
  }

  /// A spoken stop word ends the session (WP73: log where it came from,
  /// never the text).
  Future<bool> _stopWord(Transcript transcript, {required bool first}) async {
    if (!isStopWord(transcript.text)) return false;
    diagnostics?.call('stop-word source=transcript first=$first');
    await cancel(VoiceCancelReason.stopWord);
    return true;
  }

  /// [stripWakeWord] plus the `wake-strip` diagnosis (WP146, numbers only).
  String _stripWakeLogged(String text) {
    final rest = stripWakeWord(text);
    final n = _listenLog.stripSpeechSamples;
    final ms = n == null ? -1 : samplesToDuration(n).inMilliseconds;
    diagnostics?.call(wakeStripLog(text, rest, speechMs: ms));
    contentLog?.call('wake-strip', {'text': text, 'rest': rest});
    return rest;
  }

  void _announceListening(TriggerEvent? trigger, bool followUp) {
    _listenLog.followUp = followUp;
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
    contentLog?.call('stt-reject', {
      'text': transcript.text,
      'conf': transcript.confidence,
      'action': gate.name,
    });
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
    Endpoint? Function(Int16List first) onFirstFrame,
  ) {
    var first = true;
    final sub = audio.start().listen(
      (frame) {
        if (done.isCompleted || frame.isEmpty) return;
        Endpoint? early;
        final isFirst = first;
        if (first) {
          first = false;
          early = onFirstFrame(frame);
        }
        _devRec?.add(isFirst ? 'mic' : null, frame);
        if (early != null) {
          end(early);
          return;
        }
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

  /// Ends the barge-in recording that went on after the answer, unused.
  void _endBargeTail() {
    _tailSource?.endTail();
  }

  BargeTailSource? get _tailSource => switch (bargeInDetector) {
    final BargeTailSource s => s,
    _ => null,
  };

  /// The follow-up microphone has its [first] frame (WP146): the audio the
  /// barge-in recording collected since the end of the answer leads the
  /// recording, marked by the VAD. The recordings overlap: the end of the
  /// tail that the first frame repeats is cut, a hole that remains is
  /// silence (at most [_bargeTailHoleMax]; more is not a handover hole).
  /// The barge-in recording ends here. Logs numbers only (`bridge-tail`).
  Endpoint? _bridgeBargeTail(Endpointer endpointer, Int16List first) {
    final tail = _tailSource?.endTail();
    if (_tailSource == null) return null;
    if (tail == null) {
      diagnostics?.call('bridge-tail got=none');
      return null;
    }
    // The tail ends `idle` ago, the first frame covers the time since
    // `firstLen` ago: positive = hole, negative = both hold the same audio.
    final gap = tail.idle - samplesToDuration(first.length);
    var audio = tail.pcm;
    var trim = 0;
    var silence = 0;
    if (gap.isNegative) {
      trim = durationToSamples(-gap).clamp(0, audio.length).toInt();
      audio = Int16List.sublistView(audio, 0, audio.length - trim);
    } else if (gap <= _bargeTailHoleMax) {
      silence = durationToSamples(gap);
    }
    _devRec
      ?..add('tail', audio)
      ..add('silence', Int16List(silence));
    final lead = Int16List(audio.length + silence)..setAll(0, audio);
    final early = lead.isEmpty
        ? null
        : _feedPreRoll(endpointer, lead, false, 0, margin: false);
    diagnostics?.call(
      'bridge-tail ms=${samplesToDuration(tail.pcm.length).inMilliseconds} '
      'gap=${gap.inMilliseconds} '
      'trim=${samplesToDuration(trim).inMilliseconds} '
      'silence=${samplesToDuration(silence).inMilliseconds} '
      'tailDb=${_LevelLog.db(_rms(audio))} '
      'firstDb=${_LevelLog.db(_rms(first))} early=${early != null}',
    );
    return early;
  }

  static double _rms(Int16List pcm) {
    if (pcm.isEmpty) return 0;
    var sum = 0.0;
    for (final s in pcm) {
      sum += s * s;
    }
    return math.sqrt(sum / pcm.length);
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
    // WP146 diagnosis: first run of speech after the wake word (to the first
    // pause or the end of the pre-roll), only for the first feed.
    var run = 0;
    var inRun = false;
    var runDone = false;
    _listenLog.stripSpeechSamples = null;
    for (var i = from; i < preRoll.length; i += chunk) {
      final end = i + chunk < preRoll.length ? i + chunk : preRoll.length;
      final frame = Int16List.sublistView(preRoll, i, end);
      final speech = wakeEnd == null
          ? isSpeech
          : i >= marginEnd && frame.length == chunk && vad.isSpeech(frame);
      if (wakeEnd != null && margin && !runDone) {
        if (speech) {
          inRun = true;
          run += frame.length;
        } else if (inRun) {
          runDone = true;
        }
        _listenLog.stripSpeechSamples = run;
      }
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
      'mic-level s=${_second++} rms=${db(rms)} peak=${db(_peak.toDouble())} '
      'zero=${(100 * _zero / _n).round()}',
    );
    _n = 0;
    _zero = 0;
    _peak = 0;
    _sum = 0;
  }

  static int db(double v) =>
      v < 1 ? -99 : (20 * math.log(v / 32768) / math.ln10).round();
}

/// Diagnostic numbers of the recordings (WP146): when the answer ended and
/// how long the microphone took to deliver the first frame.
final class _ListenLog {
  /// When the answer stopped being spoken (null: none yet).
  DateTime? speakEnded;

  /// Whether the next recording is a follow-up one.
  bool followUp = false;

  /// Samples of the first speech run after the wake word in the pre-roll
  /// (`wake-strip` diagnosis); null when no pre-roll was fed.
  int? stripSpeechSamples;

  /// Starts the log of one recording (read at its start).
  _RecordingLog start(void Function(String)? sink, Clock clock) =>
      _RecordingLog(sink, clock, followUp, speakEnded);
}

/// The log lines `listen-open` and `listen-end` of one recording (numbers
/// only).
final class _RecordingLog {
  _RecordingLog(this._sink, this._clock, this._follow, this._speakEnded)
    : _opening = Stopwatch()..start();

  final void Function(String)? _sink;
  final Clock _clock;
  final bool _follow;
  final DateTime? _speakEnded;
  final Stopwatch _opening;

  /// The first frame arrived: how long after the end of the answer (words
  /// spoken meanwhile are lost) and after the start of the recording.
  void opened() {
    final at = _speakEnded;
    final since = at == null ? -1 : _clock.now().difference(at).inMilliseconds;
    _sink?.call(
      'listen-open follow=$_follow sinceSpeak=$since '
      'openMs=${_opening.elapsedMilliseconds}',
    );
  }

  /// The recording ended with [result].
  void ended(Endpoint? result) {
    final ms = result == null
        ? 0
        : samplesToDuration(result.pcm.length).inMilliseconds;
    _sink?.call(
      'listen-end follow=$_follow kind=${result?.kind.name} '
      'reason=${result?.reason.name} '
      'lead=${result?.speechStart?.inMilliseconds ?? -1} ms=$ms',
    );
  }
}
