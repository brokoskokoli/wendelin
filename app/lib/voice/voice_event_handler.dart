// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'voice_controller.dart';

/// Maps pipeline events to the UI state and the voice log. (Below: the
/// press-and-hold gestures of the microphone button, WP192.)
extension _VoiceEventHandler on VoiceController {
  /// WP120: the time line of the request runs from the end of the speech.
  void _onStateTraced(VoiceState s) {
    final latency = ref.read(latencyTraceProvider);
    if (s == VoiceState.transcribing) latency.begin();
    if (s == VoiceState.idle || s == VoiceState.listening) {
      latency.finishSoon();
    }
    _onState(s);
  }

  void _onEvent(VoiceEvent e) {
    switch (e) {
      case VoiceListening(:final followUp):
        state = state.copyWith(
          clearHint: true,
          clearError: true,
          clearFollowUp: !followUp,
        );
      case VoiceFollowUpListening(:final window, :final until):
        state = state.copyWith(followUpUntil: until, followUpWindow: window);
        voiceLogPipelineEvent(e);
      case VoiceConversationEnded():
        state = state.copyWith(clearFollowUp: true);
        voiceLogPipelineEvent(e);
      case VoiceTranscribed(:final transcript):
        _language = transcript.language;
        ref.read(latencyTraceProvider).sttDone();
      case VoiceNothingUnderstood(:final reason):
        voiceLog('nothing-understood', {'reason': reason});
        state = state.copyWith(
          hint: VoiceTexts.of(_language).nothingUnderstood,
        );
      case VoiceError(:final during, :final error):
        voiceLog('voice-error', {'phase': during, 'error': errorCode(error)});
        state = state.copyWith(error: voiceErrorText(uiTexts(ref), error));
      case VoiceSpeaking(:final sentence):
        _answers.spoke(sentence);
        ref.read(latencyTraceProvider).sentenceToTts();
        // Source of what is heard: the answer (not the confirmation).
        voiceLog('speak', {'source': 'answer'});
      case VoiceCancelled(:final reason, :final during):
        ref.read(latencyTraceProvider).abort();
        voiceLog('voice-cancelled', {'reason': reason, 'phase': during});
        _onCancelled(reason, during);
      case VoiceBargeIn():
        voiceLogPipelineEvent(e); // barge-in
      case VoiceHoldLimitReached():
        // WP192: the held recording is processed; tell the user why.
        voiceLogPipelineEvent(e);
        state = state.copyWith(hint: voiceHoldLimitHint);
      case VoiceAgentEvent(:final event):
        ref.read(latencyTraceProvider).agentEvent(event);
    }
  }

  // „Abgebrochen“: stop word (meta line, overlay reacts to stopCount) or a
  // tap (while listening or recognising before the agent got the request,
  // B5; during the answer the overlay closes like at a stop, WP172).
  void _onCancelled(VoiceCancelReason reason, VoiceState during) {
    final stop = reason == VoiceCancelReason.stopWord;
    final tap = reason == VoiceCancelReason.tap;
    _answers.cancelled();
    if (!stop && !tap) return;
    if (stop) _agent.addNotice(cancelledText);
    // Both: the overlay hides the old exchange and closes (setting).
    state = state.copyWith(stopCount: state.stopCount + 1, hint: cancelledText);
  }
}

/// How long the microphone button must stay pressed until it counts as
/// „held“ (WP192); a shorter press is a tap (normal endpointing).
const kHoldThreshold = Duration(milliseconds: 450);

/// What the press-down did; [VoiceControllerPress.pressUp] and
/// [VoiceControllerPress.holdStart] go on from there.
enum _PressKind {
  /// Nothing (yet, or the press is over).
  none,

  /// Idle: a normal recording was started (see [VoicePress.started]).
  started,

  /// Thinking/speaking: the request was cancelled like by a tap.
  cancelled,

  /// Already listening: nothing happened at press-down.
  listening,
}

/// State and order of one press gesture. The gesture calls run strictly one
/// after the other (a hold start or release during the model loading or the
/// permission question waits for the start), so nothing starts twice and no
/// call gets lost.
final class VoicePress {
  Future<void> _queue = Future.value();
  _PressKind _kind = _PressKind.none;
  bool _started = false;
  TriggerKind _trigger = TriggerKind.pushToTalk;
  Future<bool> Function()? _prepare;

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _queue.then((_) => op());
    _queue = next.onError((_, _) {});
    return next;
  }
}

/// Press-and-hold gestures of the microphone button (WP192). [tap] stays
/// the single action (TalkBack).
extension VoiceControllerPress on VoiceController {
  /// The finger went down. Idle: starts a normal recording right away.
  /// Listening: nothing (the release decides). Thinking/speaking (or an
  /// agent run): cancels like a tap.
  Future<void> pressDown({
    TriggerKind kind = TriggerKind.pushToTalk,
    Future<bool> Function()? prepare,
  }) => _press._enqueue(() async {
    final p = _press
      .._trigger = kind
      .._prepare = prepare
      .._started = false;
    if (state.listening) {
      p._kind = _PressKind.listening;
    } else if (state.active || ref.read(agentControllerProvider).running) {
      p._kind = _PressKind.cancelled;
      if (state.active) {
        await cancel();
      } else {
        _agent.cancel();
      }
    } else {
      p._kind = _PressKind.started;
      p._started = await start(kind, prepare: prepare);
    }
  });

  /// The hold threshold ([kHoldThreshold]) passed with the finger still
  /// down: the recording is held (no end by silence) until [pressUp]. After
  /// a cancel (thinking/speaking) a new held recording starts.
  Future<void> holdStart() => _press._enqueue(() async {
    final p = _press;
    switch (p._kind) {
      case _PressKind.none:
        return;
      case _PressKind.listening:
        _pipeline?.hold();
      case _PressKind.started:
        if (p._started) _pipeline?.hold();
      case _PressKind.cancelled:
        await _agent.idle;
        if (!ref.mounted) return;
        p._kind = _PressKind.started;
        p._started = await start(p._trigger, prepare: p._prepare);
        if (p._started) _pipeline?.hold();
    }
  });

  /// The finger went up (or the system cancelled the gesture). [held]: the
  /// threshold had passed, so the held recording is processed now.
  /// Otherwise it was a tap: it only cancels while listening (as [tap]); in
  /// the other states the press-down did the job.
  Future<void> pressUp({required bool held}) => _press._enqueue(() async {
    final p = _press;
    final kind = p._kind;
    final started = p._started;
    p._kind = _PressKind.none;
    if (held) {
      if (kind == _PressKind.listening || started) _pipeline?.release();
    } else if (kind == _PressKind.listening) {
      await cancel();
    }
  });
}

final _presses = Expando<VoicePress>('VoicePress');

extension on VoiceController {
  VoicePress get _press => _presses[this] ??= VoicePress();
}
