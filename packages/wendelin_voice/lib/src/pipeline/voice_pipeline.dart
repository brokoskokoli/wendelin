import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import '../dev/dev_clips.dart';
import '../io/audio_input.dart';
import '../io/barge_in_detector.dart';
import '../io/speech_to_text.dart';
import '../io/text_to_speech.dart';
import '../io/trigger.dart';
import '../io/voice_activity_detector.dart';
import '../speaker/speaker_match.dart';
import '../text/spoken_answer.dart';
import '../text/voice_texts.dart';
import '../tts/speech_queue.dart';
import '../wake/wake_verifier.dart' show stripWakeWord, wakeStripLog;
import 'barge_detector_sync.dart';
import 'conversation.dart';
import 'endpointer.dart';
import 'open_question.dart';
import 'speaker_identification.dart';
import 'speech_hold.dart';
import 'stt_confidence_gate.dart';
import 'voice_events.dart';
import 'voice_pipeline_config.dart';

export 'conversation.dart';
export 'voice_pipeline_config.dart';
part 'voice_pipeline_text.dart';
part 'voice_pipeline_listen.dart';
part 'voice_pipeline_record.dart';

/// The voice pipeline (concept: Auslöser → Aufnahme mit VAD → STT → Agent →
/// TTS) as a state machine:
/// `idle → listening → transcribing → thinking ⇄ speaking → idle`.
///
/// - [cancel] aborts in every state (tap); a transcript that is only a stop
///   word („Stopp“) aborts as well.
/// - The transcript goes to the agent as `UserInput(source: voice)` with
///   STT confidence and language.
/// - The answer is spoken sentence by sentence while it streams in
///   ([SpokenAnswer], [SpeechQueue]); `AgentTextReset` drops the queued,
///   not yet spoken sentences of the discarded segment. Thinking and
///   provider blocks are never spoken (they never appear as
///   `AgentTextDelta`, and thinking deltas are ignored).
/// - With [VoicePipelineConfig.conversationMode] it listens again after
///   the answer for [VoicePipelineConfig.followUpWindow]; every
///   conversation ends once with a [ConversationEndReason].
/// - With a [BargeInDetector] and [VoicePipelineConfig.bargeIn] a signal
///   during [VoiceState.speaking] stops the speech at once: „Wendelin“ (or
///   speech) starts a new utterance.
final class VoicePipeline with VoiceContentLog {
  /// Creates a pipeline. [textToSpeech] is asked for the engine before
  /// every answer with the answer language (see `TtsSelector.current`);
  /// `null` = text only.
  VoicePipeline({
    required this.audio,
    required this.vad,
    required this.stt,
    required this.agent,
    required this.textToSpeech,
    this.config = const VoicePipelineConfig(),
    this.clock = const SystemClock(),
    TriggerSource? triggers,
    this.bargeInDetector,
    this.diagnostics,
    this.speaker,
  }) {
    _triggerSub = triggers?.triggers.listen(_onTrigger);
    _bargeSub = bargeInDetector?.signals.listen(_onBargeIn);
  }

  /// Microphone.
  final AudioInput audio;

  /// Voice activity detection.
  final VoiceActivityDetector vad;

  /// Speech recognition.
  final SpeechToText stt;

  /// The agent loop.
  final AgentRun agent;

  /// Settings.
  final VoicePipelineConfig config;

  /// Detects barge-in while the answer is spoken (`null` = none).
  final BargeInDetector? bargeInDetector;

  /// Receives secret-free diagnostic event names (`barge-wait-timeout`);
  /// the app writes them to its voice log.
  final void Function(String event)? diagnostics;

  /// Speaker recognition (WP92a), `null` = off (the default: no effort).
  /// It runs in parallel to the transcription; its result hangs at
  /// `Transcript.speaker`. A failure or „unknown“ never blocks a request.
  final SpeakerRecognizer? speaker;

  /// Time source for trigger timestamps.
  final Clock clock;

  /// Resolves the speech output for the answer language (BCP 47 or `null`)
  /// before every answer (`null` = text only).
  final Future<TextToSpeech?> Function(String? language) textToSpeech;
  StreamSubscription<TriggerEvent>? _triggerSub;
  StreamSubscription<BargeInSignal>? _bargeSub;

  final _states = StreamController<VoiceState>.broadcast(sync: true);
  final _events = StreamController<VoiceEvent>.broadcast(sync: true);

  VoiceState _state = VoiceState.idle;
  int _gen = 0;
  bool _disposed = false;
  bool _convOpen = false;
  int _rounds = 0; // answered requests of the conversation
  bool _speechFailed = false;

  void Function(Endpoint?)? _endListening;
  // The microphone was kept open after a decision inside the pre-roll
  // (WP146): the live audio is the continuation of a possible re-listen.
  bool _micHeld = false;
  final _listenLog = _ListenLog();
  Endpointer? _endpointer;
  SpeechQueue? _queue;
  bool _agentRunning = false;
  Future<void> _agentDrained = Future.value();
  Future<void> _session = Future.value();
  Future<void> _listening = Future.value();
  late final _barge = BargeDetectorSync(
    detector: () => bargeInDetector,
    enabled: () => config.bargeIn != BargeInMode.off,
    state: () => _state,
    onError: (e) => _emit(VoiceError(VoiceState.speaking, e)),
    wantTail: () => _tailNext,
  );

  // The next `listening` follows an answer: the barge-in recording goes on
  // until the follow-up microphone has its first frame (WP146).
  bool _tailNext = false;

  /// Silence forced after the end of the wake word, so that its tail (the
  /// engine position is an estimate) is not mistaken for the request (WP68, WP184).
  static const wakeEndMargin = Duration(milliseconds: 350);

  /// How long a recording waits for the barge-in detector to release the mic.
  static const bargeReleaseTimeout = Duration(seconds: 2);

  /// Current state.
  VoiceState get state => _state;

  /// State changes (synchronous broadcast).
  Stream<VoiceState> get states => _states.stream;

  /// Events (synchronous broadcast).
  Stream<VoiceEvent> get events => _events.stream;

  /// Completes when the current request (including speech output) is over.
  Future<void> get whenIdle => _session;

  /// Starts listening. Returns `false` if a request is already running. The
  /// pre-roll of [trigger] (wake word) is fed to the endpointer first. A wake
  /// word pre-roll without [TriggerEvent.wakeEnd] is dropped: nothing from
  /// before the wake word may reach the recognition (privacy, WP73).
  bool start({TriggerEvent? trigger}) {
    final dropPreRoll =
        trigger?.source == TriggerKind.wakeWord && trigger?.wakeEnd == null;
    return _begin(
      trigger,
      preRoll: dropPreRoll ? null : trigger?.preRoll,
      wakeEnd: trigger?.wakeEnd,
    );
  }

  bool _begin(
    TriggerEvent? trigger, {
    Int16List? preRoll,
    bool preRollIsSpeech = false,
    bool continued = false,
    int? wakeEnd,
  }) {
    if (_disposed || _state != VoiceState.idle) return false;
    final t =
        trigger ??
        TriggerEvent(source: TriggerKind.pushToTalk, at: clock.now());
    final gen = ++_gen;
    _session = _run(
      gen,
      trigger: t,
      preRoll: preRoll,
      preRollIsSpeech: preRollIsSpeech,
      continued: continued,
      wakeEnd: wakeEnd,
    );
    return true;
  }

  /// Ends listening now (e.g. push-to-talk released) and transcribes what
  /// was captured. No effect outside [VoiceState.listening].
  void finishListening() {
    final end = _endListening;
    final endpointer = _endpointer;
    if (end == null || endpointer == null) return;
    end(endpointer.finish());
  }

  /// Aborts the current request in any state (tap). No effect when idle.
  Future<void> cancel([VoiceCancelReason reason = VoiceCancelReason.tap]) {
    if (_state == VoiceState.idle) return Future.value();
    final during = _state;
    _gen++;
    _abortActivities();
    if (reason != VoiceCancelReason.bargeIn) {
      _endConversation(switch (reason) {
        VoiceCancelReason.tap => ConversationEndReason.tap,
        VoiceCancelReason.stopWord => ConversationEndReason.stopWord,
        _ => ConversationEndReason.cancelled,
      });
    }
    _setState(VoiceState.idle);
    _emit(VoiceCancelled(reason, during: during));
    return _agentDrained;
  }

  /// Aborts everything and releases resources.
  Future<void> dispose() async {
    if (_disposed) return;
    final drained = cancel(VoiceCancelReason.disposed);
    _disposed = true;
    unawaited(_triggerSub?.cancel());
    unawaited(_bargeSub?.cancel());
    unawaited(_states.close());
    unawaited(_events.close());
    await drained;
  }

  Future<void> _run(
    int gen, {
    TriggerEvent? trigger,
    Int16List? preRoll,
    bool preRollIsSpeech = false,
    bool continued = false,
    int? wakeEnd,
  }) async {
    var followUp = false;
    var quietRejects = 0;
    // The wake word is cut from the first transcript (WP68).
    var stripWake = trigger?.source == TriggerKind.wakeWord;
    var pre = preRoll;
    var preWakeEnd = wakeEnd;
    var preRest = false; // WP146: after "only the wake word"
    if (config.conversationMode) {
      _convOpen = true;
      // The interrupted request counts as a round.
      _rounds = continued ? _rounds + 1 : 0;
    }
    while (true) {
      _tailNext = followUp;
      _setState(VoiceState.listening);
      _announceListening(trigger, followUp);
      final endpoint = await _listen(
        gen,
        followUp
            ? config.endpoint.withNoSpeechTimeout(config.followUpWindow)
            : config.endpoint,
        preRoll: followUp ? null : pre,
        preRollIsSpeech: preRollIsSpeech,
        wakeEnd: preWakeEnd,
        preRollRest: preRest,
        holdMic: stripWake && !followUp && pre != null,
        tail: followUp,
      );
      if (gen != _gen) return;
      if (endpoint == null) return _finish(gen, ConversationEndReason.error);
      if (endpoint.kind == EndpointKind.nothing) {
        if (!followUp) await _nothingUnderstood(gen, endpoint.reason);
        return _finish(gen, ConversationEndReason.silence);
      }
      var transcript = await _transcribe(gen, endpoint.pcm);
      if (gen != _gen) return;
      if (transcript == null) return _finish(gen, ConversationEndReason.error);
      if (stripWake && !followUp) {
        stripWake = false;
        final rest = _stripWakeLogged(transcript.text);
        if (rest.isEmpty && transcript.text.trim().isNotEmpty) {
          // Only the wake word: feed the pre-roll rest, then the live mic.
          pre = _preRollLeft(pre, preWakeEnd, endpoint.elapsed);
          preWakeEnd = pre == null ? null : 0;
          preRest = pre != null;
          continue;
        }
        transcript = transcript.withText(rest);
      }
      _releaseHeldMic();
      if (transcript.text.trim().isEmpty) {
        if (!followUp) {
          await _nothingUnderstood(gen, null, language: transcript.language);
        }
        return _finish(gen, ConversationEndReason.silence);
      }
      if (await _stopWord(transcript, first: !followUp && trigger != null)) {
        return;
      }
      if (followUp && isClosingPhrase(transcript.text, config.closingPhrases)) {
        return _finish(gen, ConversationEndReason.closingPhrase);
      }
      final gate = await _applyGate(gen, transcript, trigger, followUp);
      final accepted = gate == SttGateAction.accept;
      if (gate == SttGateAction.askAgain ||
          (!accepted && ++quietRejects > config.maxQuietRejects)) {
        return _finish(gen, ConversationEndReason.silence);
      }
      if (!accepted) continue; // keep listening in the same follow-up window
      quietRejects = 0;
      _setState(VoiceState.thinking);
      final problem = await _answer(gen, transcript);
      if (gen != _gen) return;
      if (!config.conversationMode) return _finish(gen);
      if (problem != null) return _finish(gen, problem);
      _rounds++;
      if (_rounds - 1 >= config.maxFollowUps) {
        return _finish(gen, ConversationEndReason.maxFollowUps);
      }
      followUp = true;
    }
  }

  void _finish(int gen, [ConversationEndReason? reason]) {
    if (gen != _gen) return;
    _releaseHeldMic();
    if (reason != null) _endConversation(reason);
    _setState(VoiceState.idle);
  }

  /// Emits the end of the conversation once (`conv-exit reason=…`).
  void _endConversation(ConversationEndReason reason) {
    if (!_convOpen) return;
    _convOpen = false;
    _emit(
      VoiceConversationEnded(reason, followUps: _rounds > 0 ? _rounds - 1 : 0),
    );
  }

  void _onBargeIn(BargeInSignal s) {
    final mode = config.bargeIn;
    if (_disposed || _state != VoiceState.speaking || mode == BargeInMode.off) {
      return;
    }
    if (s.kind == BargeInKind.speech && mode != BargeInMode.speech) return;
    _emit(VoiceBargeIn(s));
    unawaited(cancel(VoiceCancelReason.bargeIn)); // stops the queue at once
    _begin(
      TriggerEvent(source: TriggerKind.wakeWord, at: clock.now()),
      preRoll: s.preRoll,
      preRollIsSpeech: s.kind == BargeInKind.speech,
      continued: true,
    );
  }

  /// Whether [text] is a stop command: only stop words and filler words,
  /// at least one stop word („Stopp, stopp.“, „Nein, stopp bitte“).
  bool isStopWord(String text) => isStopCommand(
    text,
    stopWords: config.stopWords,
    fillerWords: config.fillerWords,
    stopPhrases: config.stopPhrases,
  );

  Future<Transcript?> _transcribe(int gen, Int16List pcm) async {
    _setState(VoiceState.transcribing);
    try {
      final who = SpeakerIdentification(
        recognizer: speaker,
        clock: clock,
        diagnostics: diagnostics,
      ).identify(pcm);
      final text = await stt.transcribe(pcm, language: config.language);
      final match = await who;
      if (gen != _gen) return null;
      final t = match == null ? text : text.withSpeaker(match);
      _emit(VoiceTranscribed(t));
      return t;
    } on Object catch (error) {
      if (gen == _gen) _emit(VoiceError(VoiceState.transcribing, error));
      return null;
    }
  }

  /// How long a request waits for the recognition at most.
  static const speakerTimeout = SpeakerIdentification.timeout;

  Future<void> _nothingUnderstood(
    int gen,
    EndpointReason? reason, {
    String? language,
  }) async {
    _emit(VoiceNothingUnderstood(reason));
    if (!config.speakNothingUnderstood) return;
    final lang = language ?? config.language;
    await _speakOnly(gen, [VoiceTexts.of(lang).nothingUnderstood], lang);
  }

  /// Speaks [sentences] outside of an answer (e.g. „nichts verstanden“).
  Future<void> _speakOnly(int gen, List<String> sentences, String? lang) async {
    final queue = await _newQueue(gen, lang);
    if (queue == null || gen != _gen) return;
    queue.addAll(sentences);
    await queue.whenIdle;
    if (_queue == queue) _queue = null;
  }

  Future<SpeechQueue?> _newQueue(int gen, String? language) async {
    TextToSpeech? tts;
    try {
      tts = await textToSpeech(language);
    } on Object catch (error) {
      if (gen == _gen) _emit(VoiceError(_state, error));
    }
    if (tts == null || gen != _gen) return null;
    return _queue = SpeechQueue(
      tts,
      voice: config.voice,
      language: language,
      rate: config.rate,
      onStart: (s) {
        if (gen != _gen) return;
        _setState(VoiceState.speaking);
        _emit(VoiceSpeaking(s));
        if (bargeInDetector case final SpokenTextSink sink) sink.spoke(s);
      },
      onIdle: () {
        if (gen == _gen && _agentRunning) _setState(VoiceState.thinking);
      },
      onError: (error) {
        if (gen != _gen) return;
        _speechFailed = true;
        _emit(VoiceError(VoiceState.speaking, error));
      },
    );
  }

  /// Runs the agent and speaks the answer. Returns why the conversation
  /// must not continue (`null` = it may).
  Future<ConversationEndReason?> _answer(int gen, Transcript transcript) async {
    _speechFailed = false;
    var failed = false;
    final confirmations = <AgentEvent>[];
    final language = transcript.language ?? config.language;
    final input = UserInput(
      text: transcript.text.trim(),
      source: InputSource.voice,
      sttConfidence: transcript.confidence,
      language: language,
      speakerId: transcript.speaker?.personId,
    );
    await _agentDrained; // a cancelled earlier run must be finished
    if (gen != _gen) return null;
    final queue = await _newQueue(gen, language);
    if (gen != _gen) return null;
    final spoken = SpokenAnswer(config: config.shortening, language: language);
    var segment = 0;
    // The `<spoken>` block of this segment was spoken (WP41, stage 2): the
    // written text of the segment stays on the screen only.
    var hasBlock = false;
    void say(List<String> sentences) =>
        queue?.addAll(sentences, segment: segment);

    // Checked mode: the written text waits for the verdict on the spoken one.
    final hold = SpeechHold();
    void releaseHeld() {
      for (final d in hold.release()) {
        say(spoken.add(d));
      }
    }

    final drained = Completer<void>();
    _agentDrained = drained.future;
    _agentRunning = true;
    try {
      await for (final e in agent.run(input)) {
        if (gen != _gen) continue; // cancelled: let the run wind down
        _emit(VoiceAgentEvent(e));
        switch (e) {
          case AgentTextDelta(:final text):
            if (!hasBlock && !hold.take(text)) say(spoken.add(text));
          case AgentSpokenHold():
            hold.start();
          case AgentSpokenVerdict(accepted: false):
            releaseHeld();
          case AgentSpokenText(:final text):
            hold.drop();
            hasBlock = true;
            say(
              SpokenAnswer.shorten(
                text,
                language: language,
                config: config.shortening,
              ),
            );
          case AgentTextReset():
            hold.drop();
            final dropped = queue?.dropSegment(segment) ?? const [];
            spoken.reset(unspoken: dropped);
            hasBlock = false;
          case ToolCallStarted() || ToolCallFinished():
            releaseHeld();
            say(spoken.endSegment());
            segment++;
            hasBlock = false;
          case AgentTextComplete():
            // The answer text is complete: read the last sentence now, the
            // receipt may still be pending (WP81).
            diagnostics?.call('answer-complete');
            releaseHeld();
            say(spoken.finish());
          case AgentDone():
            releaseHeld();
            say(spoken.finish());
          case AttestationStatusChanged(status: AttestationStatus.red):
            // The answer turned out unverified: stop what is being read and
            // say so (the warning card and the undo are shown elsewhere).
            hold.drop();
            spoken.reset();
            failed = true; // no follow-up listening after an unverified answer
            unawaited(queue?.interrupt());
            say([VoiceTexts.of(language).unverified]);
          case _ when isQuestionEvent(e):
            confirmations.add(e);
          case AgentFailed(:final error, :final message):
            if (error != AgentErrorKind.cancelled) failed = true;
            // Buffered, incomplete text of the failed answer is dropped on
            // purpose (it may stop mid-sentence); sentences already queued
            // are still spoken, then the failure in the answer language.
            if (error != AgentErrorKind.cancelled && config.speakErrors) {
              say([VoiceTexts.of(language).failure(error, message)]);
            }
          default:
            // Thinking, routing, usage, confirmations: display only.
            break;
        }
      }
    } on Object catch (error) {
      failed = true;
      if (gen == _gen) _emit(VoiceError(VoiceState.thinking, error));
    } finally {
      _agentRunning = false;
      drained.complete();
    }
    if (gen != _gen) return null;
    if (queue != null) {
      await queue.whenIdle;
      if (_queue == queue) _queue = null;
    }
    if (gen != _gen) return null;
    final open = confirmations.any(isOpenQuestion);
    if (open) return ConversationEndReason.confirmation;
    return failed || _speechFailed ? ConversationEndReason.error : null;
  }

  void _setState(VoiceState s) {
    if (_state == s) return;
    if (_state == VoiceState.speaking) _listenLog.speakEnded = clock.now();
    _state = s;
    _barge.sync(s);
    if (!_states.isClosed) _states.add(s);
  }

  void _emit(VoiceEvent e) {
    if (!_events.isClosed) _events.add(e);
  }
}
