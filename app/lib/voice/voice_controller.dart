import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../agent/agent_controller.dart';
import '../agent/conversation_state.dart';
import '../di/providers.dart';
import '../di/voice_providers.dart';
import '../ui/design/mic_button.dart';
import '../ui/screens/labels.dart';
import 'level_meter.dart';
import 'primed_audio_input.dart';
import 'voice_components.dart';
import 'voice_log.dart';

/// Number of waveform bars (as in the overlay design).
const waveBars = 6;

/// What the voice UI (microphone button, waveform, hints) shows.
@immutable
final class VoiceUiState {
  /// Creates a state.
  const VoiceUiState({
    this.phase = VoiceState.idle,
    this.levels = const [],
    this.trigger,
    this.hint,
    this.error,
    this.awaitingAnswer = false,
    this.preparing = false,
    this.tapOnly = false,
  });

  /// State of the voice pipeline.
  final VoiceState phase;

  /// Recent microphone levels (0–1), newest last, at most [waveBars].
  final List<double> levels;

  /// What started the current request.
  final TriggerKind? trigger;

  /// Neutral hint („Ich habe nichts verstanden.“).
  final String? hint;

  /// Why speech failed (microphone, recognition).
  final String? error;

  /// Listening for a spoken „ja“/„nein“ to an open confirmation.
  final bool awaitingAnswer;

  /// The microphone already records (and buffers) while the speech models
  /// still load (B11). Signal for a „Moment …“ display (WP31).
  final bool preparing;

  /// The open confirmation of a voice request can only be answered by tap
  /// (the spoken answer could not start or got no answer, B7).
  final bool tapOnly;

  /// Whether a voice request (or a spoken confirmation) is in progress.
  bool get active => phase != VoiceState.idle || awaitingAnswer || preparing;

  /// Whether the microphone is open.
  bool get listening =>
      phase == VoiceState.listening || awaitingAnswer || preparing;

  /// Whether an open confirmation may be answered by voice („Sag einfach
  /// ja oder nein“), otherwise only by tap („Antworte per Tipp“).
  bool get answersByVoice => active && !tapOnly;

  /// A copy with the given fields replaced (`clear…` resets to `null`).
  VoiceUiState copyWith({
    VoiceState? phase,
    List<double>? levels,
    TriggerKind? trigger,
    String? hint,
    bool clearHint = false,
    String? error,
    bool clearError = false,
    bool? awaitingAnswer,
    bool? preparing,
    bool? tapOnly,
  }) => VoiceUiState(
    phase: phase ?? this.phase,
    levels: levels ?? this.levels,
    trigger: trigger ?? this.trigger,
    hint: clearHint ? null : hint ?? this.hint,
    error: clearError ? null : error ?? this.error,
    awaitingAnswer: awaitingAnswer ?? this.awaitingAnswer,
    preparing: preparing ?? this.preparing,
    tapOnly: tapOnly ?? this.tapOnly,
  );
}

/// Voice requests of the app: push-to-talk on the main screen and the
/// assistant overlay (`TriggerKind.assistant`).
final voiceControllerProvider = NotifierProvider<VoiceController, VoiceUiState>(
  VoiceController.new,
);

/// How long the speech models stay loaded while the app is in the
/// background and nothing runs (B14).
final voiceReleaseDelayProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 2),
);

/// Runs the [VoicePipeline] (Aufnahme → STT → Agent → TTS) on the
/// [VoiceComponents] and answers open confirmations by voice.
///
/// The agent part goes through the [AgentController] ([ControllerAgentRun]),
/// so a spoken request appears in the conversation, is audited (with its
/// trigger) and its confirmations open the usual card. While a confirmation
/// of a voice request is open, the controller speaks a short question and
/// listens once (twice if unclear) for „ja“/„nein“ (de/fr/en,
/// [YesNoRecognizer]); a tap answers as well. If that cannot start or ends
/// without an answer, the card says „Antworte per Tipp“ ([VoiceUiState.
/// tapOnly]) and Wendelin says so; it never just stops listening (B7).
///
/// The microphone opens right after the tap and buffers while Whisper and
/// the VAD load ([PrimedAudioInput], B11). In the background the models are
/// freed after [voiceReleaseDelayProvider] ([background], B14).
///
/// Diagnostics without content go to the log ([voiceLog]).
final class VoiceController extends Notifier<VoiceUiState> {
  VoicePipeline? _pipeline;
  VoiceComponents? _components;
  MeteredAudioInput? _audio;
  PrimedAudioInput? _primed;
  final _subs = <StreamSubscription<Object?>>[];
  String? _language;
  PendingQuestion? _confirming;
  PendingQuestion? _queued;
  void Function()? _abortCapture;
  TextToSpeech? _promptTts;
  // Counts [cancel] calls: a spoken confirmation that started before a
  // cancel never goes on to listen (the stopped question returns first).
  int _cancels = 0;
  // The running agent request came from the voice pipeline.
  bool _voiceRun = false;
  // Main screen or overlay visible (prewarm, release, B11/B14).
  bool _foreground = false;
  Timer? _releaseTimer;
  // Tap → first frame / models ready, for `mic-ready` (B11).
  Stopwatch? _micWatch;
  Duration? _firstFrame;
  Duration? _loaded;
  String _micEngineModel = '';

  /// Answers are only taken from short utterances.
  static const recognizer = YesNoRecognizer();

  /// Limits of the recording for a spoken „ja“/„nein“.
  static const answerEndpoint = EndpointConfig(
    maxDuration: Duration(seconds: 5),
    noSpeechTimeout: Duration(seconds: 6),
  );

  /// Longest wait for the first microphone frame of the answer: then the
  /// microphone counts as not started (B7, H5).
  static Duration micStartTimeout = const Duration(seconds: 3);

  /// Longest spoken question (the engine may never report its end, B7).
  static Duration promptTimeout = const Duration(seconds: 15);

  @override
  VoiceUiState build() {
    ref
      ..listen(
        agentControllerProvider.select((s) => s.pending),
        (_, next) => _onPending(next),
      )
      ..listen(agentControllerProvider.select((s) => s.running), (_, running) {
        if (!running) _voiceRun = false;
      })
      // Models arrive (download, first refresh): warm up if visible.
      ..listen(voiceReadyProvider, (_, ready) {
        if (ready && _foreground) prewarm();
      })
      // Demo switched: drop the pipeline; other new components (model or
      // settings changed) are picked up at the next start (_pipelineFor).
      ..listen(demoModeProvider, (_, _) => unawaited(_reset()))
      ..onDispose(() {
        _releaseTimer?.cancel();
        unawaited(_reset());
      });
    return const VoiceUiState();
  }

  AgentController get _agent => ref.read(agentControllerProvider.notifier);

  /// Completes when the current voice request (including speech output)
  /// is over.
  Future<void> get whenIdle => _pipeline?.whenIdle ?? Future.value();

  /// Starts a voice request from [kind]. Returns `false` (with [VoiceUiState.error]
  /// set) when speech is unavailable or a request already runs. [prepare]
  /// runs once the speech models are there, e.g. asking for the microphone
  /// permission with an explanation (`ensureMicrophoneAccess`); `false`
  /// stops. Without models it is never called (hint
  /// [voiceUnavailableHint] instead of a permission dialog).
  ///
  /// With installed models the microphone opens right after [prepare] and
  /// buffers while Whisper and the VAD load (B11).
  Future<bool> start(
    TriggerKind kind, {
    Future<bool> Function()? prepare,
  }) async {
    if (state.active || ref.read(agentControllerProvider).running) {
      return false;
    }
    _releaseTimer?.cancel();
    _micWatch = Stopwatch()..start();
    _firstFrame = null;
    _loaded = null;
    final early = !ref.read(demoModeProvider) && ref.read(voiceReadyProvider);
    if (!early) return _startAfterLoading(kind, prepare);
    // Models are installed: the permission first, then the microphone,
    // while the models load (WP18 review: no permission without models).
    if (!(await prepare?.call() ?? true)) {
      state = state.copyWith(error: microphoneDeniedHint, clearHint: true);
      return false;
    }
    if (state.active || ref.read(agentControllerProvider).running) {
      return false;
    }
    final cancels = _cancels;
    // The microphone of the loaded components, or (first use) the device
    // microphone they will get.
    final primed = _primedFor(
      ref.read(activeVoiceProvider).value?.audio ??
          ref.read(audioInputProvider),
    );
    state = state.copyWith(
      trigger: kind,
      preparing: true,
      levels: const [],
      clearHint: true,
      clearError: true,
    );
    primed.prime();
    final VoiceComponents? components;
    try {
      components = await _loadComponents();
    } on Object catch (e) {
      await primed.stop();
      voiceLog('start-failed', {'reason': 'load', 'error': errorCode(e)});
      state = state.copyWith(
        preparing: false,
        error: voiceErrorText(e),
        clearHint: true,
      );
      return false;
    }
    if (components == null || cancels != _cancels) {
      await primed.stop();
      voiceLog('start-failed', {
        'reason': components == null ? 'no-models' : 'cancelled',
      });
      state = state.copyWith(
        preparing: false,
        error: components == null ? voiceUnavailableHint : null,
      );
      return false;
    }
    // Only the device microphone is opened early; other components (demo,
    // tests) record from their own input.
    if (!identical(components.audio, primed.inner)) await primed.stop();
    final pipeline = _pipelineFor(components);
    state = state.copyWith(preparing: false);
    return _run(pipeline, kind);
  }

  Future<bool> _startAfterLoading(
    TriggerKind kind,
    Future<bool> Function()? prepare,
  ) async {
    // Models first: without speech recognition there is nothing to ask the
    // microphone permission for (WP18 review, WP19).
    final VoiceComponents? components;
    try {
      components = await _loadComponents();
    } on Object catch (e) {
      voiceLog('start-failed', {'reason': 'load', 'error': errorCode(e)});
      state = state.copyWith(error: voiceErrorText(e), clearHint: true);
      return false;
    }
    if (components == null) {
      voiceLog('start-failed', {'reason': 'no-models'});
      state = state.copyWith(error: voiceUnavailableHint, clearHint: true);
      return false;
    }
    if (!(await prepare?.call() ?? true)) {
      state = state.copyWith(error: microphoneDeniedHint, clearHint: true);
      return false;
    }
    if (state.active || ref.read(agentControllerProvider).running) {
      return false;
    }
    final pipeline = _pipelineFor(components);
    state = state.copyWith(trigger: kind, clearHint: true, clearError: true);
    return _run(pipeline, kind);
  }

  bool _run(VoicePipeline pipeline, TriggerKind kind) {
    final started = pipeline.start(
      trigger: TriggerEvent(source: kind, at: ref.read(clockProvider).now()),
    );
    if (!started) voiceLog('start-failed', {'reason': 'busy'});
    return started;
  }

  /// The voice parts with their models loaded (`null`: not installed).
  Future<VoiceComponents?> _loadComponents() async {
    final components = await ref.read(activeVoiceProvider.future);
    await components?.warmUp?.call();
    _loaded = _micWatch?.elapsed;
    _micEngineModel = components?.stt.info.model ?? '';
    _logMicReady();
    return components;
  }

  void _onFirstFrame() {
    if (_micWatch == null || _firstFrame != null) return;
    _firstFrame = _micWatch!.elapsed;
    _logMicReady();
  }

  /// `mic-ready`: tap → first frame and tap → models ready (B11).
  void _logMicReady() {
    final first = _firstFrame;
    final loaded = _loaded;
    if (first == null || loaded == null) return;
    _micWatch = null;
    voiceLog('mic-ready', {
      'after': first,
      'load': loaded,
      'model': _micEngineModel,
      'trigger': state.trigger,
    });
  }


  /// Microphone button: starts push-to-talk when idle, otherwise cancels
  /// the voice request (tap aborts in every state).
  Future<void> tap({Future<bool> Function()? prepare}) async {
    if (state.active) return cancel();
    await start(TriggerKind.pushToTalk, prepare: prepare);
  }

  /// Aborts the voice request (listening, recognition, answer, speech
  /// output, a spoken confirmation). An open confirmation counts as „no“.
  Future<void> cancel() async {
    _cancels++;
    _abortCapture?.call();
    final tts = _promptTts;
    _promptTts = null;
    if (tts != null) await tts.stop();
    if (state.preparing) {
      await _primed?.stop();
      state = state.copyWith(preparing: false);
    }
    await _pipeline?.cancel();
  }

  /// The app went to the background (screen off, other app, overlay
  /// closed): stop listening and speaking and cancel the running request,
  /// spoken or typed. Nothing keeps running unseen.
  Future<void> suspend() async {
    final running = ref.read(agentControllerProvider).running;
    await cancel();
    if (running) _agent.cancel();
  }

  /// The screen is visible (main screen, unlocked overlay): load the speech
  /// models in the background, so the first tap needs no loading (B11).
  /// Nothing happens without installed models or in the demo.
  void prewarm() {
    _foreground = true;
    _releaseTimer?.cancel();
    if (ref.read(demoModeProvider) || !ref.read(voiceReadyProvider)) return;
    final watch = Stopwatch()..start();
    unawaited(() async {
      try {
        final components = await ref.read(activeVoiceProvider.future);
        await components?.warmUp?.call();
        voiceLog('prewarm', {'ms': watch.elapsed});
      } on Object catch (e) {
        voiceLog('prewarm-failed', {'error': errorCode(e)});
      }
    }());
  }

  /// The screen went to the background: [suspend], then free Whisper and
  /// the offline voice after [voiceReleaseDelayProvider] if nothing runs
  /// (B14). [prewarm] loads them again.
  Future<void> background() async {
    _foreground = false;
    await suspend();
    _releaseTimer?.cancel();
    _releaseTimer = Timer(
      ref.read(voiceReleaseDelayProvider),
      () => unawaited(_releaseIfIdle()),
    );
  }

  Future<void> _releaseIfIdle() async {
    if (_foreground ||
        state.active ||
        ref.read(agentControllerProvider).running) {
      return;
    }
    await releaseModels(reason: 'idle');
  }

  /// Frees Whisper and the offline voice now (overlay closes, idle in the
  /// background); the next request loads them again.
  Future<void> releaseModels({String reason = 'release'}) async {
    final components = ref.read(activeVoiceProvider).value;
    final release = components?.release;
    if (release == null) return;
    voiceLog('release', {'reason': reason});
    try {
      await release();
    } on Object catch (e) {
      voiceLog('release-failed', {'error': errorCode(e)});
    }
  }

  /// Replaces the state (golden tests with sample data).
  @visibleForTesting
  void seed(VoiceUiState value) => state = value;

  /// Clears hint and error (e.g. when the overlay closes).
  void clearMessages() =>
      state = state.copyWith(clearHint: true, clearError: true);

  PrimedAudioInput _primedFor(AudioInput inner) {
    final existing = _primed;
    if (existing != null && identical(existing.inner, inner)) return existing;
    if (existing != null) unawaited(existing.stop());
    return _primed = PrimedAudioInput(inner, onFirstFrame: _onFirstFrame);
  }

  VoicePipeline _pipelineFor(VoiceComponents components) {
    final existing = _pipeline;
    if (existing != null && identical(components, _components)) {
      return existing;
    }
    unawaited(existing?.dispose());
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    unawaited(_audio?.dispose());
    final audio = MeteredAudioInput(_primedFor(components.audio));
    final pipeline = VoicePipeline(
      audio: audio,
      vad: components.vad,
      stt: components.stt,
      agent: ControllerAgentRun(_agent, trigger: () => state.trigger?.name),
      textToSpeech: components.textToSpeech,
      config: components.config,
      clock: ref.read(clockProvider),
    );
    _components = components;
    _audio = audio;
    _pipeline = pipeline;
    _subs
      ..add(pipeline.states.listen(_onState))
      ..add(pipeline.events.listen(_onEvent))
      ..add(audio.levels.listen(_onLevel));
    return pipeline;
  }

  Future<void> _reset() async {
    _abortCapture?.call();
    final pipeline = _pipeline;
    _pipeline = null;
    _components = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    await pipeline?.dispose();
    await _audio?.dispose();
    _audio = null;
    await _primed?.stop();
    _primed = null;
  }

  void _onState(VoiceState s) {
    // From here the agent request belongs to the voice pipeline.
    if (s == VoiceState.thinking) _voiceRun = true;
    state = state.copyWith(
      phase: s,
      levels: s == VoiceState.listening ? const [] : state.levels,
    );
  }

  void _onLevel(double level) {
    if (!state.listening) return;
    final levels = [...state.levels, level];
    state = state.copyWith(
      levels: levels.length > waveBars
          ? levels.sublist(levels.length - waveBars)
          : levels,
    );
  }

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
      case VoiceAgentEvent():
        break;
    }
  }

  void _onPending(PendingQuestion? next) {
    final current = _confirming;
    if (current != null && !identical(current, next)) {
      // Answered by tap, or the run ended: stop listening for the answer.
      _abortCapture?.call();
    }
    if (next == null || next.answered) {
      _queued = null;
      if (state.tapOnly) state = state.copyWith(tapOnly: false);
      return;
    }
    if (state.tapOnly) state = state.copyWith(tapOnly: false);
    if (identical(current, next)) return;
    if (current != null) {
      // A new question while the previous one still winds down: it is
      // asked as soon as that one is over (B7, H4).
      _queued = next;
      return;
    }
    _maybeConfirm(next);
  }

  /// Whether the running agent request is a voice request.
  bool get _voiceRequest {
    final pipeline = _pipeline;
    return _voiceRun || (pipeline != null && pipeline.state != VoiceState.idle);
  }

  void _maybeConfirm(PendingQuestion question) {
    if (!_voiceRequest) {
      // Typed request: the card answers by tap; no line per question.
      return;
    }
    unawaited(_confirmByVoice(question));
  }

  Future<void> _confirmByVoice(PendingQuestion question) async {
    final cancels = _cancels;
    String? closed() {
      if (cancels != _cancels) return 'not-open(cancelled)';
      final pending = ref.read(agentControllerProvider).pending;
      if (question.answered) return 'not-open(answered)';
      if (!identical(pending, question)) return 'not-open(replaced)';
      return null;
    }

    // Exactly one exit line per question: `confirm-exit reason=…`.
    var reason = 'unknown';
    var byTap = false;
    _confirming = question;
    final watch = Stopwatch()..start();
    voiceLog('confirm-start', {
      'phase': _pipeline?.state,
      'strict': strictAnswer(question),
    });
    try {
      final components = _components;
      final audio = _audio;
      if (components == null || audio == null) {
        reason = 'no-components';
        byTap = true;
        return;
      }
      if (audio.isRunning) {
        // The previous recording has not stopped yet (B7, H2): stop it.
        voiceLog('confirm-wait', {'reason': 'audio-running'});
        try {
          await audio.stop().timeout(const Duration(seconds: 2));
        } on Object catch (e) {
          voiceLog('confirm-wait-failed', {'error': errorCode(e)});
        }
        if (audio.isRunning) {
          reason = 'audio-running';
          byTap = true;
          return;
        }
      }
      TextToSpeech? tts;
      try {
        tts = await components.textToSpeech(_language);
      } on Object catch (e) {
        voiceLog('confirm-tts-error', {'error': errorCode(e)});
      }
      _promptTts = tts;
      for (var attempt = 0; attempt < 2; attempt++) {
        if (closed() case final r?) {
          reason = r;
          return;
        }
        final prompt = attempt == 0
            ? confirmationPrompt(question, _language)
            : repeatPrompt(_language);
        await _sayBounded(tts, prompt, attempt: attempt);
        if (closed() case final r?) {
          reason = r;
          return;
        }
        state = state.copyWith(awaitingAnswer: true, levels: const []);
        final capture = await _capture(components, audio);
        state = state.copyWith(awaitingAnswer: false);
        if (closed() case final r?) {
          reason = r;
          return;
        }
        final pcm = capture.pcm;
        if (pcm == null) {
          reason = 'capture-null(${capture.reason})';
          byTap = true;
          return;
        }
        final Transcript transcript;
        try {
          transcript = await components.stt.transcribe(
            pcm,
            language: components.config.language,
          );
        } on Object catch (e) {
          voiceLog('confirm-stt-error', {'error': errorCode(e)});
          state = state.copyWith(error: voiceErrorText(e));
          reason = 'stt-error';
          byTap = true;
          return;
        }
        if (closed() case final r?) {
          reason = r;
          return;
        }
        final answer = recognizer.parse(
          transcript.text,
          strict: strictAnswer(question),
        );
        if (answer != null) {
          reason = 'answered(${answer.name})';
          _agent.answer(approved: answer == YesNo.yes);
          return;
        }
        voiceLog('confirm-unclear', {'attempt': attempt + 1});
      }
      reason = 'unclear';
      byTap = true;
    } on Object catch (e) {
      reason = 'error(${errorCode(e)})';
      byTap = true;
      state = state.copyWith(error: voiceErrorText(e));
    } finally {
      _confirming = null;
      _abortCapture = null;
      final tts = _promptTts;
      _promptTts = null;
      if (state.awaitingAnswer) state = state.copyWith(awaitingAnswer: false);
      voiceLog('confirm-exit', {
        'reason': reason,
        'tap': byTap,
        'ms': watch.elapsed,
      });
      if (byTap && closed() == null) await _answerByTap(tts);
      _askQueued();
    }
  }

  /// The spoken answer did not work: the card says „Antworte per Tipp“
  /// and Wendelin says it once (B7).
  Future<void> _answerByTap(TextToSpeech? tts) async {
    state = state.copyWith(tapOnly: true);
    if (tts == null) return;
    _promptTts = tts;
    try {
      await _sayBounded(tts, tapAnswerPrompt(_language), source: 'tap-hint');
    } finally {
      if (identical(_promptTts, tts)) _promptTts = null;
    }
  }

  void _askQueued() {
    final next = _queued;
    _queued = null;
    if (next == null || next.answered) return;
    if (!identical(ref.read(agentControllerProvider).pending, next)) return;
    _maybeConfirm(next);
  }

  /// Speaks [text] after the answer sentences; never hangs longer than
  /// [promptTimeout] and never throws (the card shows the question too).
  Future<void> _sayBounded(
    TextToSpeech? tts,
    String text, {
    int attempt = 0,
    String source = 'confirm',
  }) async {
    if (tts == null) {
      voiceLog('confirm-prompt', {'source': source, 'tts': false});
      return;
    }
    final watch = Stopwatch()..start();
    try {
      await _say(tts, text).timeout(promptTimeout);
      voiceLog('confirm-prompt', {
        'source': source,
        'attempt': attempt + 1,
        'ms': watch.elapsed,
      });
    } on TimeoutException {
      voiceLog('confirm-prompt', {'source': source, 'result': 'tts-timeout'});
      await tts.stop();
    } on Object catch (e) {
      voiceLog('confirm-prompt', {
        'source': source,
        'result': 'tts-error',
        'error': errorCode(e),
      });
    }
  }

  Future<void> _say(TextToSpeech tts, String text) async {
    // Let the answer sentences before the tool call finish first.
    if (tts.state == TtsState.speaking) {
      await tts.states
          .firstWhere((s) => s == TtsState.idle)
          .timeout(const Duration(seconds: 30), onTimeout: () => TtsState.idle);
      // `firstWhere` resumes inside the engine's state event; speaking from
      // there would fire a new state event while it still fires one.
      await Future<void>.delayed(Duration.zero);
    }
    await tts.speak(text, language: _language);
  }

  /// Records one short utterance; `pcm` is `null` if nothing was said, the
  /// capture was aborted or the microphone did not deliver ([reason]).
  Future<({Int16List? pcm, String reason})> _capture(
    VoiceComponents components,
    AudioInput audio,
  ) async {
    const limits = answerEndpoint;
    final endpointer = Endpointer(limits);
    final done = Completer<(Endpoint?, String)>();
    void end(Endpoint? e, String reason) {
      if (!done.isCompleted) done.complete((e, reason));
    }

    _abortCapture = () => end(null, 'aborted');
    final watch = Stopwatch()..start();
    var frames = 0;
    StreamSubscription<Int16List>? sub;
    voiceLog('confirm-listen-start');
    try {
      components.vad.reset();
      sub = audio.start().listen(
        (frame) {
          if (done.isCompleted || frame.isEmpty) return;
          if (frames++ == 0) {
            voiceLog('confirm-mic', {'after': watch.elapsed});
          }
          final e = endpointer.add(
            frame,
            speech: components.vad.isSpeech(frame),
          );
          if (e != null) end(e, 'endpoint');
        },
        onError: (Object error) {
          voiceLog('confirm-mic-error', {'error': errorCode(error)});
          state = state.copyWith(error: voiceErrorText(error));
          end(null, 'stream-error');
        },
        onDone: () => end(endpointer.finish(), 'stream-done'),
      );
    } on Object catch (error) {
      voiceLog('confirm-mic-error', {'error': errorCode(error)});
      end(null, 'start-error');
    }
    // The microphone must deliver soon, otherwise it did not start (H5).
    final micGuard = Timer(micStartTimeout, () {
      if (frames == 0) end(null, 'mic-timeout');
    });
    final guard = Timer(
      limits.noSpeechTimeout + limits.maxDuration,
      () => end(endpointer.finish(EndpointReason.maxDuration), 'guard'),
    );
    final (result, how) = await done.future;
    micGuard.cancel();
    guard.cancel();
    try {
      if (audio.isRunning) await audio.stop();
    } on Object catch (e) {
      voiceLog('confirm-mic-error', {'error': errorCode(e)});
    }
    unawaited(sub?.cancel());
    _abortCapture = null;
    final utterance = result?.kind == EndpointKind.utterance;
    final reason = result == null
        ? how
        : utterance
        ? 'utterance'
        : 'no-speech';
    voiceLog('confirm-listen-end', {
      'result': reason,
      'ms': watch.elapsed,
      'frames': frames,
    });
    return (pcm: utterance ? result!.pcm : null, reason: reason);
  }
}

/// [AgentRun] of the voice pipeline on the [AgentController]: the request
/// runs like a typed one (conversation, audit with [trigger], undo,
/// confirmations), only the events also go back to the pipeline.
final class ControllerAgentRun implements AgentRun {
  /// Creates the adapter; [trigger] names what started the request.
  ControllerAgentRun(this.controller, {required this.trigger});

  /// The conversation controller.
  final AgentController controller;

  /// Name of the current trigger (`pushToTalk`, `assistant`).
  final String? Function() trigger;

  @override
  Stream<AgentEvent> run(UserInput input) =>
      controller.submit(input, trigger: trigger());

  @override
  void cancel() => controller.cancel();
}

/// Microphone button state: listening (also for a spoken answer),
/// thinking while a voice or typed request runs, idle when speech is
/// [available], otherwise disabled.
MicState micStateFor(
  VoiceUiState voice, {
  required bool available,
  required bool running,
}) {
  if (voice.listening) return MicState.listening;
  if (voice.active || running) return MicState.thinking;
  return available ? MicState.idle : MicState.disabled;
}

/// German text for a failure of a voice component.
String voiceErrorText(Object error) => switch (error) {
  VoiceException(:final message) => message,
  _ => 'Sprache hat nicht geklappt: $error',
};

/// Whether a spoken „yes“ to [question] must be strict (1–2 yes words):
/// `external` tools and escalations below the privacy level.
bool strictAnswer(PendingQuestion question) => switch (question) {
  ToolQuestion(:final event) => event.risk == RiskLevel.external,
  EscalationQuestion() => true,
};

/// Spoken question for an open confirmation, in [language] (de/fr/en);
/// names the action.
String confirmationPrompt(PendingQuestion question, String? language) {
  final lang = VoiceTexts.of(language).language;
  return switch (question) {
    ToolQuestion(:final event) => switch (lang) {
      'fr' => '${_actionFr(event.call.name)} Oui ou non ?',
      'en' => '${_actionEn(event.call.name)} Yes or no?',
      _ => '${confirmationTexts(event.call.name).title} Ja oder nein?',
    },
    EscalationQuestion(:final toName) => switch (lang) {
      'fr' => 'Transmettre à $toName ? Oui ou non ?',
      'en' => 'Hand over to $toName? Yes or no?',
      _ => 'An $toName übergeben? Ja oder nein?',
    },
  };
}

String _spokenTool(String tool) =>
    tool.replaceAll('__', ' ').replaceAll('_', ' ');

bool _deletes(String tool) => RegExp('delete|remove|clear|forget')
    .hasMatch(tool.contains('__') ? tool.substring(tool.indexOf('__')) : tool);

String _actionFr(String tool) => switch (tool) {
  'calendar__delete_event' => 'Supprimer le rendez-vous ?',
  'obsidian__replace_section' => 'Remplacer la section de la note ?',
  'lists__clear_completed' => 'Supprimer les éléments terminés ?',
  _ when _deletes(tool) => 'Supprimer : ${_spokenTool(tool)} ?',
  _ => 'Exécuter : ${_spokenTool(tool)} ?',
};

String _actionEn(String tool) => switch (tool) {
  'calendar__delete_event' => 'Delete the appointment?',
  'obsidian__replace_section' => 'Replace the section of the note?',
  'lists__clear_completed' => 'Clear the completed items?',
  _ when _deletes(tool) => 'Delete: ${_spokenTool(tool)}?',
  _ => 'Run: ${_spokenTool(tool)}?',
};

/// Spoken request to repeat an unclear answer.
String repeatPrompt(String? language) =>
    switch (VoiceTexts.of(language).language) {
      'fr' => 'Dis oui ou non, s’il te plaît.',
      'en' => 'Please say yes or no.',
      _ => 'Bitte sag ja oder nein.',
    };

/// Spoken note that the open confirmation now needs a tap (B7).
String tapAnswerPrompt(String? language) =>
    switch (VoiceTexts.of(language).language) {
      'fr' => 'Réponds en touchant l’écran, s’il te plaît.',
      'en' => 'Please answer with a tap.',
      _ => 'Antworte bitte per Tipp.',
    };
