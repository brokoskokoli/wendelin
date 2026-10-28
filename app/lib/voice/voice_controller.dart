import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../agent/agent_controller.dart';
import '../agent/chat_entry.dart';
import '../agent/conversation_state.dart';
import '../agent/outgoing_preview.dart';
import '../di/preferences.dart';
import '../di/providers.dart';
import '../di/sms_drafts.dart';
import '../di/voice_providers.dart';
import '../l10n/l10n.dart';
import '../platform/assistant_platform.dart';
import '../platform/voice/capture_profile_follower.dart';
import '../platform/voice/ducking_tts.dart' show SpeechFocus;
import '../platform/voice/record_audio_input.dart';
import 'answer_capture.dart';
import 'app_voice_reporter.dart';
import 'confirm_prompts.dart';
import 'controller_agent_run.dart';
import 'conversation_offer.dart';
import 'level_meter.dart';
import 'locked_agent_run.dart';
import 'primed_audio_input.dart';
import 'voice_components.dart';
import 'voice_log.dart';
import 'voice_models_check.dart';
import 'voice_ui_state.dart';
import 'voice_usage.dart';
import 'wake/wake_pre_roll.dart';

export 'confirm_prompts.dart';
export 'controller_agent_run.dart';
export 'locked_agent_run.dart';
export 'voice_ui_state.dart';
export 'wake/wake_pre_roll.dart' show WakePreRoll, WakeTail, wakeGapMs;

part 'voice_answer_text.dart';
part 'voice_confirmation.dart';
part 'voice_event_handler.dart';
part 'voice_prepare.dart';

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
  int _muteMicSamples = 0;
  PrimedAudioInput? _primed;
  final _subs = <StreamSubscription<Object?>>[];
  String? _language;
  final _answers = SpokenAnswerTracker();
  CaptureProfileFollower? _profile;
  PendingQuestion? _confirming;
  PendingQuestion? _queued;
  void Function()? _abortCapture;
  TextToSpeech? _promptTts;
  // Counts [cancel] calls: a spoken confirmation that started before a
  // cancel never goes on to listen (the stopped question returns first).
  int _cancels = 0;
  // The running agent request came from the voice pipeline.
  bool _voiceRun = false;
  bool _lastByVoice = false; // request kind of the current/last run (B9)
  // Request kind per tool card (B9: „Zurückgenommen.“ follows the card).
  final _callByVoice = <String, bool>{};
  // Main screen or overlay visible (prewarm, release, B11/B14).
  bool _foreground = false;
  // Main screen: warm up only for people who use speech (base load).
  bool _warmOnlyIfUsed = false;
  Timer? _releaseTimer;
  // Tap → first frame / models ready, for `mic-ready` (B11).
  Stopwatch? _micWatch;
  Duration? _firstFrame;
  // The hit whose service microphone still records (WP146, WP68).
  final _wake = WakeHandoffTracker();
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
    _focus = ref.read(speechFocusProvider);
    final appVoice = AppVoiceReporter(ref.read(assistantPlatformProvider));
    final trim = ref.read(memoryTrimSourceProvider).levels.listen(onMemoryTrim);
    ref
      ..listen(
        agentControllerProvider.select((s) => s.pending),
        (_, next) => _onPending(next),
      )
      ..listen(agentControllerProvider.select((s) => s.running), (_, running) {
        if (running) _lastByVoice = _voiceRun;
        if (!running) _voiceRun = false;
      })
      ..listen(agentControllerProvider.select((s) => s.entries), (prev, now) {
        // IDs can repeat (call_N): new entries overwrite, new topic clears.
        var from = prev?.length ?? 0;
        if (now.length < from) _callByVoice.clear();
        if (now.length < from) from = 0;
        for (final e in now.skip(from).whereType<ToolEntry>()) {
          _callByVoice[e.id] = _lastByVoice;
        }
      })
      // Models arrive (download, first refresh): warm up if visible.
      ..listen(voiceReadyProvider, (_, ready) {
        if (ready && _foreground) unawaited(_warm());
      })
      // Demo switched: drop the pipeline; other new components (model or
      // settings changed) are picked up at the next start (_pipelineFor).
      ..listen(demoModeProvider, (_, _) => unawaited(_reset()))
      ..onDispose(() {
        appVoice.dispose();
        unawaited(trim.cancel());
        _releaseTimer?.cancel();
        unawaited(_reset());
      });
    listenSelf((_, next) => appVoice.update(next));
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
  /// [voiceUnavailableError] instead of a permission dialog).
  ///
  /// With installed models the microphone opens right after [prepare] and
  /// buffers while Whisper and the VAD load (B11).
  Future<bool> start(
    TriggerKind kind, {
    Future<bool> Function()? prepare,
    Future<WakePreRoll?> Function()? takePreRoll,
    int muteMicSamples = 0,
  }) async {
    _muteMicSamples = muteMicSamples;
    _wake.lastSampleAt = null;
    if (state.active || ref.read(agentControllerProvider).running) {
      return false;
    }
    _releaseTimer?.cancel();
    // `clock`: tests measure on a fake clock.
    _micWatch = clock.stopwatch()..start();
    _firstFrame = null;
    _wake.reset();
    _loaded = null;
    final demo = ref.read(demoModeProvider);
    var ready = !demo && ref.read(voiceReadyProvider);
    if (!demo && !ready && !voiceModelsChecked(ref)) {
      // Fresh engine (overlay): the installed models are not checked yet;
      // look at the two needed ones only (the full check runs anyway).
      ready = await voiceModelsInstalled(ref);
      if (!ref.mounted) return false;
    }
    if (!ready) return _startAfterLoading(kind, prepare, takePreRoll);
    if (state.active || ref.read(agentControllerProvider).running) {
      return false;
    }
    // Models are installed (WP18 review). The microphone opens right away
    // and buffers while they load; without the permission it does not record
    // (the input checks it), the explanation may come up meanwhile.
    final cancels = _cancels;
    // The loaded components' microphone, or (first use) the device one.
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
    // The hit's recording ends right before this microphone opens (WP68).
    final preRoll = takePreRoll == null ? null : await takePreRoll();
    if (!ref.mounted) return false;
    if (cancels != _cancels) {
      // Cancelled while taking the hit (WP93: the audio went elsewhere):
      // the microphone does not open.
      state = state.copyWith(preparing: false);
      unawaited(preRoll?.finish?.call());
      return false;
    }
    _wake.begin(preRoll, primed.head); // before the microphone opens
    primed.prime();
    final denied = await _askPrepare(prepare, ref);
    if (denied != null || !ref.mounted) return _failStart(primed, denied);
    if (primed.failed) {
      // Permission granted just now: open the microphone again.
      await primed.stop();
      primed.prime();
    }
    final VoiceComponents? components;
    try {
      components = await _loadComponents();
    } on Object catch (e) {
      voiceLog('start-failed', {'reason': 'load', 'error': errorCode(e)});
      final text = ref.mounted ? voiceErrorText(uiTexts(ref), e) : null;
      return _failStart(primed, text);
    }
    if (components == null || cancels != _cancels || !ref.mounted) {
      voiceLog('start-failed', {
        'reason': components == null ? 'no-models' : 'cancelled',
      });
      return _failStart(
        primed,
        components == null ? voiceUnavailableError : null,
        clearHint: false,
      );
    }
    // Only the device microphone is opened early; other components (demo,
    // tests) record from their own input.
    if (!identical(components.audio, primed.inner)) {
      await primed.stop();
      _wake.noFrameExpected();
    }
    final pipeline = _pipelineFor(components);
    state = state.copyWith(preparing: false);
    final bridged = _wake.kept(preRoll) ? await _wake.close(preRoll) : preRoll;
    if (!ref.mounted || cancels != _cancels) return _failStart(primed, null);
    return _run(pipeline, kind, bridged);
  }

  /// The start failed after the microphone opened: closes it and shows
  /// [error] (nothing if the container is gone already).
  Future<bool> _failStart(
    PrimedAudioInput primed,
    String? error, {
    bool clearHint = true,
  }) async {
    unawaited(_wake.close(_wake.handoff, wait: false));
    await primed.stop();
    if (!ref.mounted) return false;
    state = state.copyWith(
      preparing: false,
      error: error,
      clearHint: clearHint,
    );
    return false;
  }

  Future<bool> _startAfterLoading(
    TriggerKind kind,
    Future<bool> Function()? prepare,
    Future<WakePreRoll?> Function()? takePreRoll,
  ) async {
    // Models first: without speech recognition there is nothing to ask the
    // microphone permission for (WP18 review, WP19).
    final VoiceComponents? components;
    try {
      components = await _loadComponents();
    } on Object catch (e) {
      voiceLog('start-failed', {'reason': 'load', 'error': errorCode(e)});
      if (!ref.mounted) return false;
      state = state.copyWith(
        error: voiceErrorText(uiTexts(ref), e),
        clearHint: true,
      );
      return false;
    }
    if (!ref.mounted) return false;
    if (components == null) {
      voiceLog('start-failed', {'reason': 'no-models'});
      state = state.copyWith(error: voiceUnavailableError, clearHint: true);
      return false;
    }
    final denied = await _askPrepare(prepare, ref);
    if (!ref.mounted) return false;
    if (denied != null) {
      state = state.copyWith(error: denied, clearHint: true);
      return false;
    }
    if (state.active || ref.read(agentControllerProvider).running) {
      return false;
    }
    final pipeline = _pipelineFor(components);
    final cancels = _cancels;
    state = state.copyWith(trigger: kind, clearHint: true, clearError: true);
    var preRoll = takePreRoll == null ? null : await takePreRoll();
    // Cancelled while taking the hit (WP93): nothing starts.
    if (cancels != _cancels || !ref.mounted) {
      unawaited(preRoll?.finish?.call());
      return false;
    }
    // The microphone of the pipeline opens only now: the service stops at
    // once (as before WP146), the hole stays.
    if (_wake.kept(preRoll)) preRoll = await _wake.close(preRoll);
    return _run(pipeline, kind, preRoll);
  }

  bool _run(VoicePipeline pipeline, TriggerKind kind, [WakePreRoll? preRoll]) {
    _audio?.muteNextStart(preRoll?.muteMicSamples ?? _muteMicSamples);
    _muteMicSamples = 0;
    // (Without the early microphone the first frame comes after this.)
    if (_firstFrame == null) _wake.lastSampleAt = preRoll?.lastSampleAtMs;
    final started = pipeline.start(
      trigger: TriggerEvent(
        source: kind,
        at: ref.read(clockProvider).now(),
        preRoll: preRoll?.pcm,
        wakeEnd: preRoll?.wakeEnd,
      ),
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

  void _onFirstFrame(int samples) {
    if (_micWatch == null || _firstFrame != null) return;
    _firstFrame = _micWatch!.elapsed;
    _wake.onFirstFrame(samples);
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
  Future<void> cancel([VoiceCancelReason why = VoiceCancelReason.tap]) async {
    _cancels++;
    _abortCapture?.call();
    final tts = _promptTts;
    _promptTts = null;
    if (tts != null) await tts.stop();
    if (!ref.mounted) return;
    if (state.preparing) {
      await _primed?.stop();
      if (!ref.mounted) return;
      state = state.copyWith(preparing: false);
    }
    await _pipeline?.cancel(why);
  }

  /// The app went to the background (screen off, other app, overlay
  /// closed): stop listening and speaking and cancel the running request,
  /// spoken or typed. Nothing keeps running unseen.
  Future<void> suspend() async {
    final running = ref.read(agentControllerProvider).running;
    await cancel(VoiceCancelReason.suspend);
    if (running && ref.mounted) _agent.cancel();
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

  /// Android `onTrimMemory` ([level]): under real memory pressure the
  /// models are freed even with „Modell im Speicher halten“, unless a
  /// request is running (the next one loads them again).
  @visibleForTesting
  Future<void> onMemoryTrim(int level) async {
    if (!isMemoryPressure(level) ||
        state.active ||
        ref.read(agentControllerProvider).running) {
      return;
    }
    await releaseModels(reason: memoryPressureReason);
  }

  Future<void> _releaseIfIdle() async {
    final busy = _foreground || state.active;
    if (busy || ref.read(agentControllerProvider).running) return;
    await releaseModels(reason: 'idle');
  }

  /// Frees Whisper and the offline voice now (overlay closes, idle in the
  /// background); the next request loads them again.
  ///
  /// With „Modell im Speicher halten“ only memory pressure frees them
  /// ([mayReleaseModels], WP103); on overlay close the detector goes anyway.
  Future<void> releaseModels({String reason = 'release'}) async {
    final keep = ref.read(voiceSettingsProvider).value?.keepModelLoaded == true;
    final components = ref.read(activeVoiceProvider).value;
    if (!mayReleaseModels(reason, keepLoaded: keep)) {
      voiceLog('release-skipped', {'reason': reason});
      if (reason == 'overlay-close') components?.releaseDetector?.call();
      return;
    }
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
    unawaited(_profile?.dispose());
    _profile = null;
    final audio = MeteredAudioInput(tapMic(ref, _primedFor(components.audio)));
    final pipeline = VoicePipeline(
      audio: audio,
      vad: components.vad,
      stt: components.stt,
      agent: lockGateFor(
        ref,
        inner: ControllerAgentRun(_agent, trigger: () => state.trigger?.name),
        trigger: () => state.trigger?.name ?? 'assistant',
      ),
      textToSpeech: components.textToSpeech,
      bargeInDetector: components.bargeInDetector,
      speaker: components.speaker,
      diagnostics: voiceLog,
      config: components.config,
      clock: ref.read(clockProvider),
    ).withDevLog(ref);
    _components = components;
    _audio = audio;
    _pipeline = pipeline;
    // Source of the microphone follows the speech output (K23 c).
    if (components.audio case final ProfiledAudioInput input) {
      _profile = CaptureProfileFollower(input, pipeline.states);
    }
    _subs
      ..add(pipeline.states.listen(_onStateTraced))
      ..add(pipeline.events.listen(_onEvent))
      ..add(audio.levels.listen(_onLevel));
    return pipeline;
  }

  // Read in build: a dispose callback must not read providers.
  late SpeechFocus _focus;

  Future<void> _reset() async {
    _abortCapture?.call();
    final pipeline = _pipeline;
    _pipeline = null;
    _components = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    // The state stream is cancelled: nobody would clear busy any more.
    _focus.busy = false;
    await _profile?.dispose();
    _profile = null;
    await pipeline?.dispose();
    await _audio?.dispose();
    _audio = null;
    await _primed?.stop();
    _primed = null;
  }

  void _onState(VoiceState s) {
    // From here the agent request belongs to the voice pipeline.
    if (s == VoiceState.thinking) _voiceRun = true;
    // The ducking focus stays for the whole answer, also between sentences.
    _focus.busy = s == VoiceState.thinking || s == VoiceState.speaking;
    state = state.copyWith(
      phase: s,
      levels: s == VoiceState.listening ? const [] : state.levels,
      clearFollowUp: s != VoiceState.listening,
    );
    // After the events of the same moment (a cancel emits idle first).
    if (s == VoiceState.idle) scheduleMicrotask(_offerConversation);
  }

  void _offerConversation() {
    if (!ref.mounted || state.phase != VoiceState.idle) return;
    if (_answers.finished(ref.read(clockProvider).now())) {
      unawaited(ref.read(conversationOfferProvider.notifier).offer());
    }
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

  /// Undoes [callId]: stops a spoken answer at once, adds „Zurückgenommen.“
  /// and speaks it if the request came by voice (B9). Returns the text, or
  /// `null` if the undo failed.
  Future<String?> undo(String callId) async {
    if (_voiceRun || state.phase != VoiceState.idle)
      await cancel(VoiceCancelReason.undo);
    final tts = _promptTts;
    _promptTts = null;
    if (tts != null) await tts.stop();
    final byVoice = _callByVoice[callId] ?? _lastByVoice;
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
}

/// German text for a failure of a voice component.
String voiceErrorText(AppLocalizations l, Object error) => switch (error) {
  VoiceException(kind: VoiceErrorKind.modelMissing) => l.voiceErrorModelMissing,
  VoiceException(kind: VoiceErrorKind.modelBroken) => l.voiceErrorModelBroken,
  VoiceException(kind: VoiceErrorKind.busy) => l.voiceErrorMicBusy,
  VoiceException(:final message) => message,
  _ => l.voiceErrorGeneric, // never the raw message (WP64)
};
