import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../io/audio_input.dart';
import '../io/speech_to_text.dart';
import '../io/text_to_speech.dart';
import '../io/trigger.dart';
import '../io/voice_activity_detector.dart';
import '../text/spoken_answer.dart';
import '../text/voice_texts.dart';
import '../tts/speech_queue.dart';
import 'endpointer.dart';
import 'voice_events.dart';

/// Settings of the [VoicePipeline].
@immutable
final class VoicePipelineConfig {
  /// Creates a configuration.
  const VoicePipelineConfig({
    this.endpoint = const EndpointConfig(),
    this.language,
    this.shortening = const SpeechShortening(),
    this.stopWords = defaultStopWords,
    this.fillerWords = defaultFillerWords,
    this.stopPhrases = defaultStopPhrases,
    this.conversationMode = false,
    this.followUpWindow = const Duration(seconds: 5),
    this.voice,
    this.rate = 1.0,
    this.listenGrace = const Duration(seconds: 3),
    this.speakNothingUnderstood = true,
    this.speakErrors = true,
  });

  /// Stop words (lower case) in de/fr/en.
  static const defaultStopWords = {
    // de
    'stopp', 'stop', 'halt', 'abbrechen', 'abbruch', 'aufhören', 'ruhe',
    // fr
    'arrête', 'arrêtez', 'annule', 'annuler', 'stoppe',
    // en
    'cancel', 'quiet', 'enough',
  };

  /// Words that may accompany a stop word („Stopp bitte“, „Nein, stopp“).
  /// Multi-word stop commands (lower case, words separated by spaces).
  static const defaultStopPhrases = {
    // de
    'hör auf', 'hört auf', 'hören sie auf', 'sei still', 'sei ruhig',
    // fr
    'arrête ça', 'arrête ca', 'tais toi', 'taisez vous', 'ça suffit',
    'ca suffit',
    // en
    'stop it', 'stop that', 'be quiet', 'that is enough',
  };

  static const defaultFillerWords = {
    // de
    'bitte', 'nein', 'jetzt', 'sofort', 'mal', 'doch', 'ok', 'okay', 'danke',
    // fr
    'non', 'maintenant', 's', 'il', 'te', 'vous', 'plaît', 'plait', 'toi',
    'merci', 'ça', 'ca', 'tout', 'de', 'suite',
    // en
    'please', 'no', 'now', 'it', 'that', 'thanks',
  };

  /// Endpointing limits (pre-roll, end silence, maximum, minimum speech).
  final EndpointConfig endpoint;

  /// Fixed STT language (`de`, `fr`, `en`); `null` = detect automatically.
  final String? language;

  /// Limits of the spoken answer.
  final SpeechShortening shortening;

  /// A transcript that consists only of these words and [fillerWords]
  /// (with at least one stop word, repetitions allowed) aborts the request.
  /// While the answer is spoken there is no barge-in yet (v0.4), so then
  /// only tapping ([VoicePipeline.cancel]) stops it.
  final Set<String> stopWords;

  /// Words allowed next to a stop word.
  final Set<String> fillerWords;

  /// Phrases that count like a stop word („Hör auf!“, „arrête ça“,
  /// „stop it“).
  final Set<String> stopPhrases;

  /// Conversation mode (from M4, off by default): after an answer, keep
  /// listening for [followUpWindow] for a follow-up question.
  final bool conversationMode;

  /// Follow-up window of the conversation mode (concept: 5 s).
  final Duration followUpWindow;

  /// TTS voice id; `null` = engine default for the answer language.
  final String? voice;

  /// TTS speech rate.
  final double rate;

  /// Wall-clock safety margin on top of [EndpointConfig.maxDuration] in
  /// case the microphone stops delivering frames.
  final Duration listenGrace;

  /// Whether „Ich habe nichts verstanden“ is spoken.
  final bool speakNothingUnderstood;

  /// Whether the message of a failed agent run is spoken.
  final bool speakErrors;
}

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
///   the answer for [VoicePipelineConfig.followUpWindow].
final class VoicePipeline {
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
  }) {
    _triggerSub = triggers?.triggers.listen(_onTrigger);
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

  /// Time source for trigger timestamps.
  final Clock clock;

  /// Resolves the speech output for the answer language (BCP 47 or `null`)
  /// before every answer (`null` = text only).
  final Future<TextToSpeech?> Function(String? language) textToSpeech;
  StreamSubscription<TriggerEvent>? _triggerSub;

  final _states = StreamController<VoiceState>.broadcast(sync: true);
  final _events = StreamController<VoiceEvent>.broadcast(sync: true);

  VoiceState _state = VoiceState.idle;
  int _gen = 0;
  bool _disposed = false;

  void Function(Endpoint?)? _endListening;
  Endpointer? _endpointer;
  SpeechQueue? _queue;
  bool _agentRunning = false;
  Future<void> _agentDrained = Future.value();
  Future<void> _session = Future.value();
  Future<void> _listening = Future.value();

  /// Current state.
  VoiceState get state => _state;

  /// State changes (synchronous broadcast).
  Stream<VoiceState> get states => _states.stream;

  /// Events (synchronous broadcast).
  Stream<VoiceEvent> get events => _events.stream;

  /// Completes when the current request (including speech output) is over.
  Future<void> get whenIdle => _session;

  /// Starts listening. Returns `false` if a request is already running.
  bool start({TriggerEvent? trigger}) {
    if (_disposed || _state != VoiceState.idle) return false;
    final t =
        trigger ??
        TriggerEvent(source: TriggerKind.pushToTalk, at: clock.now());
    final gen = ++_gen;
    _session = _run(gen, trigger: t);
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
    unawaited(_states.close());
    unawaited(_events.close());
    await drained;
  }

  void _onTrigger(TriggerEvent e) {
    if (_state != VoiceState.idle) {
      unawaited(cancel(VoiceCancelReason.retrigger));
    }
    start(trigger: e);
  }

  void _abortActivities() {
    final end = _endListening;
    if (end != null) end(null);
    if (_agentRunning) agent.cancel();
    final q = _queue;
    _queue = null;
    if (q != null) unawaited(q.stop());
  }

  Future<void> _run(int gen, {TriggerEvent? trigger}) async {
    var followUp = false;
    while (true) {
      _setState(VoiceState.listening);
      _emit(
        VoiceListening(trigger: followUp ? null : trigger, followUp: followUp),
      );
      final endpoint = await _listen(
        gen,
        followUp
            ? config.endpoint.withNoSpeechTimeout(config.followUpWindow)
            : config.endpoint,
      );
      if (gen != _gen) return;
      if (endpoint == null) return _finish(gen); // microphone error
      if (endpoint.kind == EndpointKind.nothing) {
        // The follow-up window just closes quietly.
        if (!followUp) await _nothingUnderstood(gen, endpoint.reason);
        return _finish(gen);
      }
      final transcript = await _transcribe(gen, endpoint.pcm);
      if (gen != _gen || transcript == null) return _finish(gen);
      if (transcript.text.trim().isEmpty) {
        if (!followUp) {
          await _nothingUnderstood(gen, null, language: transcript.language);
        }
        return _finish(gen);
      }
      if (isStopWord(transcript.text)) {
        await cancel(VoiceCancelReason.stopWord);
        return;
      }
      _setState(VoiceState.thinking);
      await _answer(gen, transcript);
      if (gen != _gen) return;
      if (!config.conversationMode) return _finish(gen);
      followUp = true;
    }
  }

  void _finish(int gen) {
    if (gen == _gen) _setState(VoiceState.idle);
  }

  /// Whether [text] is a stop command: only stop words and filler words,
  /// at least one stop word („Stopp, stopp.“, „Nein, stopp bitte“).
  bool isStopWord(String text) {
    final words = text
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.isNotEmpty)
        .toList();
    // Words covered by a stop phrase count as stop words.
    final stop = [for (final w in words) config.stopWords.contains(w)];
    for (final phrase in config.stopPhrases) {
      final p = phrase.split(' ');
      for (var i = 0; i + p.length <= words.length; i++) {
        var match = true;
        for (var k = 0; k < p.length && match; k++) {
          match = words[i + k] == p[k];
        }
        if (match) stop.fillRange(i, i + p.length, true);
      }
    }
    var any = false;
    for (var i = 0; i < words.length; i++) {
      if (stop[i]) {
        any = true;
      } else if (!config.fillerWords.contains(words[i])) {
        return false;
      }
    }
    return any;
  }

  /// Records one utterance. Recordings are serialized: a new one waits
  /// until the previous (e.g. just cancelled) one has stopped the
  /// microphone, and each only clears its own hooks.
  Future<Endpoint?> _listen(int gen, EndpointConfig limits) {
    final previous = _listening;
    final run = _listenAfter(previous, gen, limits);
    _listening = run.then((_) {});
    return run;
  }

  Future<Endpoint?> _listenAfter(
    Future<void> previous,
    int gen,
    EndpointConfig limits,
  ) async {
    await previous;
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
    final guards = <Timer>[];
    _endListening = end;
    _endpointer = endpointer;
    try {
      vad.reset();
      sub = audio.start().listen(
        (frame) {
          if (done.isCompleted || frame.isEmpty) return;
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
      // Safety nets in wall-clock time in case the microphone stops
      // delivering frames: before speech after the no-speech timeout,
      // otherwise after the maximum duration (each plus a grace period).
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
    try {
      if (sub != null && audio.isRunning) await audio.stop();
    } on Object catch (error) {
      _emit(VoiceError(VoiceState.listening, error));
    }
    // Not awaited: for a finished stream `cancel` returns a shared root-zone
    // future, and there is nothing left to wait for.
    unawaited(sub?.cancel());
    return result;
  }

  Future<Transcript?> _transcribe(int gen, Int16List pcm) async {
    _setState(VoiceState.transcribing);
    try {
      final t = await stt.transcribe(pcm, language: config.language);
      if (gen != _gen) return null;
      _emit(VoiceTranscribed(t));
      return t;
    } on Object catch (error) {
      if (gen == _gen) _emit(VoiceError(VoiceState.transcribing, error));
      return null;
    }
  }

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
      },
      onIdle: () {
        if (gen == _gen && _agentRunning) _setState(VoiceState.thinking);
      },
      onError: (error) {
        if (gen == _gen) _emit(VoiceError(VoiceState.speaking, error));
      },
    );
  }

  Future<void> _answer(int gen, Transcript transcript) async {
    final language = transcript.language ?? config.language;
    final input = UserInput(
      text: transcript.text.trim(),
      source: InputSource.voice,
      sttConfidence: transcript.confidence,
      language: language,
    );
    await _agentDrained; // a cancelled earlier run must be finished
    if (gen != _gen) return;
    final queue = await _newQueue(gen, language);
    if (gen != _gen) return;
    final spoken = SpokenAnswer(config: config.shortening, language: language);
    var segment = 0;
    // The `<spoken>` block of this segment was spoken (WP41, stage 2): the
    // written text of the segment stays on the screen only.
    var hasBlock = false;
    void say(List<String> sentences) =>
        queue?.addAll(sentences, segment: segment);

    final drained = Completer<void>();
    _agentDrained = drained.future;
    _agentRunning = true;
    try {
      await for (final e in agent.run(input)) {
        if (gen != _gen) continue; // cancelled: let the run wind down
        _emit(VoiceAgentEvent(e));
        switch (e) {
          case AgentTextDelta(:final text):
            if (!hasBlock) say(spoken.add(text));
          case AgentSpokenText(:final text):
            hasBlock = true;
            say(
              SpokenAnswer.shorten(
                text,
                language: language,
                config: config.shortening,
              ),
            );
          case AgentTextReset():
            final dropped = queue?.dropSegment(segment) ?? const [];
            spoken.reset(unspoken: dropped);
            hasBlock = false;
          case ToolCallStarted() || ToolCallFinished():
            say(spoken.endSegment());
            segment++;
            hasBlock = false;
          case AgentDone():
            say(spoken.finish());
          case AgentFailed(:final error, :final message):
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
      if (gen == _gen) _emit(VoiceError(VoiceState.thinking, error));
    } finally {
      _agentRunning = false;
      drained.complete();
    }
    if (gen != _gen || queue == null) return;
    await queue.whenIdle;
    if (_queue == queue) _queue = null;
  }

  void _setState(VoiceState s) {
    if (_state == s) return;
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  void _emit(VoiceEvent e) {
    if (!_events.isClosed) _events.add(e);
  }
}
