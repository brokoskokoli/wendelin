import 'dart:async';

import 'package:wendelin_voice/wendelin_voice.dart';

import '../../voice/voice_controller.dart';
import '../design/design.dart';

/// Binds the hold gesture of the microphone button to the [controller]
/// (WP192): press, hold threshold, release.
MicGesture micGestureFor(
  VoiceController controller,
  TriggerKind kind,
  Future<bool> Function() prepare,
) => MicGesture(
  onDown: () => unawaited(controller.pressDown(kind: kind, prepare: prepare)),
  onHold: () => unawaited(controller.holdStart()),
  onUp: (held) => unawaited(controller.pressUp(held: held)),
  onAbort: () => unawaited(controller.pressAbort()),
);
