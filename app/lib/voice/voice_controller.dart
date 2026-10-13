import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../agent/agent_controller.dart';
import '../agent/conversation_state.dart';
import '../di/preferences.dart';
import '../di/providers.dart';
import '../di/voice_providers.dart';
import 'answer_capture.dart';
import 'confirm_prompts.dart';
import 'controller_agent_run.dart';
import 'level_meter.dart';
import 'primed_audio_input.dart';
import 'voice_components.dart';
import 'voice_log.dart';
import 'voice_ui_state.dart';
import 'voice_usage.dart';

export 'confirm_prompts.dart';
export 'controller_agent_run.dart';
export 'voice_ui_state.dart';

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
  bool _lastByVoice = false; // for the spoken „Zurückgenommen.“ (B9)
  // Main screen or overlay visible (prewarm, release, B11/B14).
  bool _foreground = false;
  // Main screen: warm up only for people who use speech (base load).
  bool _warmOnlyIfUsed = false;
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
  @visibleForTesting
  static Duration micStartTimeout = const Duration(seconds: 3);

  /// Longest spoken question (the engine may never report its end, B7).
  @visibleForTesting
  static Duration promptTimeout = const Duration(seconds: 15);

  @override
  VoiceUiState build() {
    ref
      ..listen(
        agentControllerProvider.select((s) => s.pending),
        (_, next) => _onPending(next),
      )
      ..listen(agentControllerProvider.select((s) => s.running), (_, running) {
        if (running) _lastByVoice = _voiceRun;
        if (!running) _voiceRun = false;
      })
      // Models arrive (download, first refresh): warm up if visible.
      ..listen(voiceReadyProvider, (_, ready) {
        if (ready && _foreground) unawaited(_warm());
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
    // `clock`: tests measure on a fake clock.
    _micWatch = clock.stopwatch()..start();
    _firstFrame = null;
    _loaded = null;
    final demo = ref.read(demoModeProvider);
    var ready = !demo && ref.read(voiceReadyProvider);
    if (!demo && !ready && !_modelsChecked()) {
      // Fresh engine (overlay): the installed models are not checked yet;
      // look at the two needed ones only (the full check runs anyway).
      ready = await _modelsInstalled();
    }
    if (!ready) return _startAfterLoading(kind, prepare);
    if (state.active || ref.read(agentControllerProvider).running) {
      return false;
    }
    // Models are installed (WP18 review: no permission question without
    // them). The microphone opens right away and buffers while the models
    // load; without the permission it does not record (the input checks
    // it), and the explanation may come up meanwhile.
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
    if (!(await prepare?.call() ?? true)) {
      await primed.stop();
      state = state.copyWith(
        preparing: false,
        error: microphoneDeniedHint,
        clearHint: true,
      );
      return false;
    }
    if (primed.failed) {
      // Permission granted just now: open the microphone again.
      await primed.stop();
      primed.prime();
    }
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

  /// Whether the installed state of the chosen Whisper and Silero is
  /// known (a fresh engine checks it in the background first).
  bool _modelsChecked() {
    final states = ref.read(modelStatesProvider.notifier);
    final stt =
        ref.read(voiceSettingsProvider).value?.sttModel ??
        const VoiceSettings().sttModel;
    return states.of(stt).phase != ModelPhase.unknown &&
        states.of(SpeechModelCatalog.sileroVad.id).phase != ModelPhase.unknown;
  }

  Future<bool> _modelsInstalled() async {
    try {
      final service = await ref.read(speechModelServiceProvider.future);
      final catalog = ref.read(speechModelCatalogProvider);
      final settings = await ref.read(voiceSettingsProvider.future);
      for (final id in [settings.sttModel, SpeechModelCatalog.sileroVad.id]) {
        final model = catalog.byId(id);
        if (model == null || !await service.isInstalled(model)) return false;
      }
      return true;
    } on Object {
      return false;
    }
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
    if (started) unawaited(noteVoiceUse(ref));
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
  ///
  /// [onlyIfUsed] (main screen): only if speech was used within
  /// [voiceRecentUseProvider], so people who only type carry no Whisper
  /// (base load); otherwise the first tap loads, and the microphone buffers
  /// meanwhile.
  void prewarm({bool onlyIfUsed = false}) {
    _foreground = true;
    _warmOnlyIfUsed = onlyIfUsed;
    _releaseTimer?.cancel();
    unawaited(_warm());
  }

  Future<void> _warm() async {
    if (ref.read(demoModeProvider) || !ref.read(voiceReadyProvider)) return;
    if (_warmOnlyIfUsed && !await voiceUsedRecently(ref)) {
      voiceLog('prewarm-skip', {'reason': 'unused'});
      return;
    }
    final watch = Stopwatch()..start();
    try {
      final components = await ref.read(activeVoiceProvider.future);
      await components?.warmUp?.call();
      voiceLog('prewarm', {'ms': watch.elapsed});
    } on Object catch (e) {
      voiceLog('prewarm-failed', {'error': errorCode(e)});
    }
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

  /// Forgets the loaded components while a request runs (test of the
  /// `no-components` exit of the spoken confirmation, B7).
  @visibleForTesting
  void forgetComponents() {
    _components = null;
    _audio = null;
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
        _onCancelled(reason, during);
      case VoiceAgentEvent():
        break;
    }
  }

  // „Abgebrochen“: stop word (meta line, overlay reacts to stopCount) or
  // a tap before the agent got the request (B5).
  void _onCancelled(VoiceCancelReason reason, VoiceState during) {
    if (reason == VoiceCancelReason.stopWord) {
      _agent.addNotice(cancelledText);
      state = state.copyWith(
        stopCount: state.stopCount + 1,
        hint: cancelledText,
      );
    } else if (reason == VoiceCancelReason.tap &&
        (during == VoiceState.listening || during == VoiceState.transcribing)) {
      state = state.copyWith(hint: cancelledText);
    }
  }

  /// Undoes [callId]: stops a spoken answer at once, adds „Zurückgenommen.“
  /// and speaks it if the request came by voice (B9). Returns the text, or
  /// `null` if the undo failed.
  Future<String?> undo(String callId) async {
    if (state.phase == VoiceState.speaking) await _pipeline?.cancel();
    final byVoice = _lastByVoice;
    final language = byVoice ? _language : ref.read(languageProvider);
    if (!await _agent.undo(callId)) return null;
    final text = undoneText(language);
    _agent.addNotice(text);
    final components = _components;
    if (byVoice && components != null) {
      _promptTts = await components
          .textToSpeech(language)
          .catchError((Object _) => null);
      await sayBounded(
        _promptTts,
        text,
        language: language,
        timeout: promptTimeout,
        source: 'undo',
      );
      _promptTts = null;
    }
    return text;
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
        await sayBounded(
          tts,
          prompt,
          language: _language,
          timeout: promptTimeout,
          attempt: attempt,
        );
        if (closed() case final r?) {
          reason = r;
          return;
        }
        state = state.copyWith(awaitingAnswer: true, levels: const []);
        final capture = await captureAnswer(
          components,
          audio,
          limits: answerEndpoint,
          micStartTimeout: micStartTimeout,
          onAbort: (abort) => _abortCapture = abort,
          onError: (e) => state = state.copyWith(error: voiceErrorText(e)),
        );
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
      await sayBounded(
        tts,
        tapAnswerPrompt(_language),
        language: _language,
        timeout: promptTimeout,
        source: 'tap-hint',
      );
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
}

/// German text for a failure of a voice component.
String voiceErrorText(Object error) => switch (error) {
  VoiceException(:final message) => message,
  _ => 'Sprache hat nicht geklappt: $error',
};
