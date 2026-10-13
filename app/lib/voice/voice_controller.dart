import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../agent/agent_controller.dart';
import '../agent/conversation_state.dart';
import '../di/providers.dart';
import '../ui/design/mic_button.dart';
import '../ui/screens/labels.dart';
import 'level_meter.dart';
import 'voice_components.dart';

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

  /// Whether a voice request (or a spoken confirmation) is in progress.
  bool get active => phase != VoiceState.idle || awaitingAnswer;

  /// Whether the microphone is open.
  bool get listening => phase == VoiceState.listening || awaitingAnswer;

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
  }) => VoiceUiState(
    phase: phase ?? this.phase,
    levels: levels ?? this.levels,
    trigger: trigger ?? this.trigger,
    hint: clearHint ? null : hint ?? this.hint,
    error: clearError ? null : error ?? this.error,
    awaitingAnswer: awaitingAnswer ?? this.awaitingAnswer,
  );
}

/// Voice requests of the app: push-to-talk on the main screen and the
/// assistant overlay (`TriggerKind.assistant`).
final voiceControllerProvider = NotifierProvider<VoiceController, VoiceUiState>(
  VoiceController.new,
);

/// Runs the [VoicePipeline] (Aufnahme → STT → Agent → TTS) on the
/// [VoiceComponents] and answers open confirmations by voice.
///
/// The agent part goes through the [AgentController] ([ControllerAgentRun]),
/// so a spoken request appears in the conversation, is audited (with its
/// trigger) and its confirmations open the usual card. While a confirmation
/// of a voice request is open, the controller speaks a short question and
/// listens once (twice if unclear) for „ja“/„nein“ (de/fr/en,
/// [YesNoRecognizer]); a tap answers as well.
final class VoiceController extends Notifier<VoiceUiState> {
  VoicePipeline? _pipeline;
  VoiceComponents? _components;
  MeteredAudioInput? _audio;
  final _subs = <StreamSubscription<Object?>>[];
  String? _language;
  PendingQuestion? _confirming;
  void Function()? _abortCapture;

  /// Answers are only taken from short utterances.
  static const recognizer = YesNoRecognizer();

  /// Limits of the recording for a spoken „ja“/„nein“.
  static const answerEndpoint = EndpointConfig(
    maxDuration: Duration(seconds: 5),
    noSpeechTimeout: Duration(seconds: 6),
  );

  @override
  VoiceUiState build() {
    ref.listen(
      agentControllerProvider.select((s) => s.pending),
      (_, next) => _onPending(next),
    );
    // New components (demo switched, WP17 model loaded): rebuild lazily.
    ref.listen(voiceComponentsProvider, (_, _) => unawaited(_reset()));
    ref.onDispose(() => unawaited(_reset()));
    return const VoiceUiState();
  }

  AgentController get _agent => ref.read(agentControllerProvider.notifier);

  /// Completes when the current voice request (including speech output)
  /// is over.
  Future<void> get whenIdle => _pipeline?.whenIdle ?? Future.value();

  /// Starts a voice request from [kind]. Returns `false` (with [VoiceUiState.error]
  /// set) when speech is unavailable or a request already runs.
  Future<bool> start(TriggerKind kind) async {
    if (state.active || ref.read(agentControllerProvider).running) {
      return false;
    }
    final VoiceComponents? components;
    try {
      components = await ref.read(voiceComponentsProvider.future);
    } on Object catch (e) {
      state = state.copyWith(error: 'Sprache nicht verfügbar: $e');
      return false;
    }
    if (components == null) {
      state = state.copyWith(error: voiceUnavailableHint, clearHint: true);
      return false;
    }
    if (!(await components.prepare?.call() ?? true)) {
      state = state.copyWith(
        error: 'Ohne Mikrofon-Zugriff geht nur Text.',
        clearHint: true,
      );
      return false;
    }
    final pipeline = _pipelineFor(components);
    state = state.copyWith(trigger: kind, clearHint: true, clearError: true);
    return pipeline.start(
      trigger: TriggerEvent(source: kind, at: ref.read(clockProvider).now()),
    );
  }

  /// Microphone button: starts push-to-talk when idle, otherwise cancels
  /// the voice request (tap aborts in every state).
  Future<void> tap() async {
    if (state.active) return cancel();
    await start(TriggerKind.pushToTalk);
  }

  /// Aborts the voice request (listening, recognition, answer, speech
  /// output, a spoken confirmation). An open confirmation counts as „no“.
  Future<void> cancel() async {
    _abortCapture?.call();
    await _pipeline?.cancel();
  }

  /// Replaces the state (golden tests with sample data).
  @visibleForTesting
  void seed(VoiceUiState value) => state = value;

  /// Clears hint and error (e.g. when the overlay closes).
  void clearMessages() =>
      state = state.copyWith(clearHint: true, clearError: true);

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
    final audio = MeteredAudioInput(components.audio);
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
  }

  void _onState(VoiceState s) => state = state.copyWith(
    phase: s,
    levels: s == VoiceState.listening ? const [] : state.levels,
  );

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
      case VoiceNothingUnderstood():
        state = state.copyWith(
          hint: VoiceTexts.of(_language).nothingUnderstood,
        );
      case VoiceError(:final error):
        state = state.copyWith(error: voiceErrorText(error));
      case VoiceCancelled() || VoiceAgentEvent() || VoiceSpeaking():
        break;
    }
  }

  void _onPending(PendingQuestion? next) {
    final current = _confirming;
    if (current != null && !identical(current, next)) {
      // Answered by tap, or the run ended: stop listening for the answer.
      _abortCapture?.call();
    }
    if (next == null || next.answered || _confirming != null) return;
    if (_pipeline?.state == VoiceState.idle || _pipeline == null) return;
    unawaited(_confirmByVoice(next));
  }

  bool _stillOpen(PendingQuestion q) {
    final pending = ref.read(agentControllerProvider).pending;
    return identical(pending, q) && !q.answered;
  }

  Future<void> _confirmByVoice(PendingQuestion question) async {
    final components = _components;
    final audio = _audio;
    if (components == null || audio == null || audio.isRunning) return;
    _confirming = question;
    try {
      final tts = await components.textToSpeech(_language);
      for (var attempt = 0; attempt < 2; attempt++) {
        if (!_stillOpen(question)) return;
        final prompt = attempt == 0
            ? confirmationPrompt(question, _language)
            : repeatPrompt(_language);
        await _say(tts, prompt);
        if (!_stillOpen(question)) return;
        state = state.copyWith(awaitingAnswer: true, levels: const []);
        final pcm = await _capture(components, audio);
        state = state.copyWith(awaitingAnswer: false);
        if (pcm == null || !_stillOpen(question)) return;
        final transcript = await components.stt.transcribe(
          pcm,
          language: components.config.language,
        );
        if (!_stillOpen(question)) return;
        final answer = recognizer.parse(transcript.text);
        if (answer != null) {
          _agent.answer(approved: answer == YesNo.yes);
          return;
        }
      }
    } on Object catch (e) {
      state = state.copyWith(error: voiceErrorText(e));
    } finally {
      _confirming = null;
      _abortCapture = null;
      if (state.awaitingAnswer) state = state.copyWith(awaitingAnswer: false);
    }
  }

  Future<void> _say(TextToSpeech? tts, String text) async {
    if (tts == null) return;
    // Let the answer sentences before the tool call finish first.
    if (tts.state == TtsState.speaking) {
      await tts.states
          .firstWhere((s) => s == TtsState.idle)
          .timeout(const Duration(seconds: 30), onTimeout: () => TtsState.idle);
    }
    await tts.speak(text, language: _language);
  }

  /// Records one short utterance; `null` if nothing was said or the
  /// capture was aborted.
  Future<Int16List?> _capture(
    VoiceComponents components,
    AudioInput audio,
  ) async {
    const limits = answerEndpoint;
    final endpointer = Endpointer(limits);
    final done = Completer<Endpoint?>();
    void end(Endpoint? e) {
      if (!done.isCompleted) done.complete(e);
    }

    _abortCapture = () => end(null);
    components.vad.reset();
    final sub = audio.start().listen(
      (frame) {
        if (done.isCompleted || frame.isEmpty) return;
        final e = endpointer.add(frame, speech: components.vad.isSpeech(frame));
        if (e != null) end(e);
      },
      onError: (Object error) {
        state = state.copyWith(error: voiceErrorText(error));
        end(null);
      },
      onDone: () => end(endpointer.finish()),
    );
    final guard = Timer(
      limits.noSpeechTimeout + limits.maxDuration,
      () => end(endpointer.finish(EndpointReason.maxDuration)),
    );
    final result = await done.future;
    guard.cancel();
    if (audio.isRunning) await audio.stop();
    unawaited(sub.cancel());
    _abortCapture = null;
    return result?.kind == EndpointKind.utterance ? result!.pcm : null;
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

/// Spoken question for an open confirmation, in [language] (de/fr/en).
String confirmationPrompt(PendingQuestion question, String? language) =>
    switch (VoiceTexts.of(language).language) {
      'fr' => 'Je confirme ? Oui ou non ?',
      'en' => 'Shall I go ahead? Yes or no?',
      _ => switch (question) {
        ToolQuestion(:final event) =>
          '${confirmationTexts(event.call.name).title} Ja oder nein?',
        EscalationQuestion(:final toName) =>
          'An $toName übergeben? Ja oder nein?',
      },
    };

/// Spoken request to repeat an unclear answer.
String repeatPrompt(String? language) =>
    switch (VoiceTexts.of(language).language) {
      'fr' => 'Dis oui ou non, s’il te plaît.',
      'en' => 'Please say yes or no.',
      _ => 'Bitte sag ja oder nein.',
    };
