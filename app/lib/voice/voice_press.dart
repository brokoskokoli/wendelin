part of 'voice_controller.dart';

/// How long the microphone button must stay pressed until it counts as
/// „held“ (WP192); a shorter press is a tap (normal endpointing).
const kHoldThreshold = Duration(milliseconds: 450);

/// What the press-down did; [VoiceControllerPress.pressUp] and
/// [VoiceControllerPress.holdStart] go on from there.
enum _PressKind {
  /// Nothing (yet, or the press is over).
  none,

  /// Idle: a normal recording was started (see [_VoicePress._started]).
  started,

  /// Thinking/speaking: the request was cancelled like by a tap.
  cancelled,

  /// Already listening: the recording is held from press-down on.
  listening,
}

/// State and order of one press gesture. The gesture calls run strictly one
/// after the other (a hold start or release during the model loading or the
/// permission question waits for the start), so nothing starts twice and no
/// call gets lost.
final class _VoicePress {
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
  /// Listening: holds right away (the release decides). Thinking/speaking (or an
  /// agent run): cancels like a tap.
  Future<void> pressDown({
    TriggerKind kind = TriggerKind.pushToTalk,
    Future<bool> Function()? prepare,
  }) => _press._enqueue(() async {
    final p = _press
      .._trigger = kind
      .._prepare = prepare
      .._started = false;
    if (_isListening) {
      p._kind = _PressKind.listening;
      // Right away: the silence end or the follow-up timeout must not close
      // the window within the threshold time (the tap cancels anyway).
      _pipeline?.hold();
    } else if (_isActive || _agentRunning) {
      p._kind = _PressKind.cancelled;
      if (_isActive) {
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
        if (!_isMounted) return;
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

  /// The press went away without a release (the button was removed before
  /// the threshold): only the hold from [pressDown] is lifted, the listening
  /// goes on with normal endpointing (no cancel).
  Future<void> pressAbort() => _press._enqueue(() async {
    final p = _press;
    final kind = p._kind;
    p._kind = _PressKind.none;
    if (kind == _PressKind.listening) _pipeline?.unhold();
  });
}

final _presses = Expando<_VoicePress>('VoicePress');

extension on VoiceController {
  _VoicePress get _press => _presses[this] ??= _VoicePress();
}
