import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../agent/agent_controller.dart';
import '../../di/wake_settings.dart';
import '../../platform/assistant_platform.dart';
import '../../platform/wake/wake_platform.dart';
import '../voice_controller.dart';
import '../voice_log.dart';
import 'wake_pre_roll.dart';

/// Tells the main screen when another route is pushed over it or removed
/// again (dialog, sheet, settings): registered with the app's navigator
/// (WP93).
final RouteObserver<ModalRoute<void>> wakeRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// WP93: whether a wake word hit continues the conversation in the chat of
/// the main app (otherwise the overlay opens with a new conversation, K41).
/// Kotlin asks with the flag it keeps; this is the second, authoritative
/// look at the moment of the hit.
abstract final class WakeChatPolicy {
  /// Chat visible: the app is in the foreground ([resumed]), the main
  /// screen is the top route ([routeCurrent], no dialog, sheet or other
  /// screen above it) and the device is not [locked].
  static bool accepts({
    required bool resumed,
    required bool routeCurrent,
    required bool locked,
  }) => resumed && routeCurrent && !locked;
}

/// WP93: the chat side of a wake word hit. Reports the visibility of the
/// chat to the wake word service, answers its question per hit, runs the
/// listening through the same [VoiceController] path as the overlay (pre-roll,
/// tone, conversation mode, barge-in, „Stopp“) and tells the service when
/// the turn is over so it listens again (counterpart of the overlay
/// closing). Never two listeners: the service stays quiet from the hit
/// until [WakePlatform.chatDone].
class WakeChatSession {
  /// Creates the session; [prepare] asks for the microphone permission
  /// like the microphone button does.
  WakeChatSession({
    required this.container,
    required this.prepare,
    this.doneDelay = const Duration(milliseconds: 400),
  }) {
    _platform.onWakeHit = _onHit;
    _subs = [
      container.listen(voiceControllerProvider, (_, _) => _check()),
      container.listen(
        agentControllerProvider.select((s) => s.running),
        (_, _) => _check(),
      ),
    ];
    _report();
  }

  /// Where the providers live.
  final ProviderContainer container;

  /// Microphone permission with explanation (`prepare` of the voice start).
  final Future<bool> Function() prepare;

  /// How long the chat must stay idle before the service is told.
  final Duration doneDelay;

  late final List<ProviderSubscription<Object?>> _subs;
  bool _resumed =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool _routeCurrent = true;
  bool? _reported;
  bool _owned = false;
  bool _starting = false;
  bool _disposed = false;
  Timer? _idleTimer;

  WakePlatform get _platform => container.read(wakePlatformProvider);

  /// The turn started by a hit is running (tests).
  @visibleForTesting
  bool get owned => _owned;

  /// The app comes to the foreground or leaves it.
  void setResumed(bool resumed) {
    _resumed = resumed;
    _report();
  }

  /// The main screen is (not) the top route.
  void setRouteCurrent(bool current) {
    _routeCurrent = current;
    _report();
  }

  void _report() {
    final visible = _resumed && _routeCurrent;
    if (visible == _reported) return;
    _reported = visible;
    unawaited(_platform.setChatVisible(visible: visible));
  }

  /// The service asks; `true` takes the hit (the service waits for the
  /// chat to take the audio), `false` lets the overlay open.
  Future<bool> _onHit() async {
    final locked = await container.read(assistantPlatformProvider).isLocked();
    final accepts =
        !_disposed &&
        WakeChatPolicy.accepts(
          resumed: _resumed,
          routeCurrent: _routeCurrent,
          locked: locked,
        );
    voiceLog('wake-chat-ask', {'accepts': accepts});
    if (!accepts) return false;
    _owned = true;
    _starting = true;
    _idleTimer?.cancel();
    // After the answer: Kotlin must know the chat owns the hit before the
    // handoff is taken, else it refuses the take.
    Timer.run(() => unawaited(_listen()));
    return true;
  }

  Future<void> _listen() async {
    final assistant = container.read(assistantPlatformProvider);
    final voice = container.read(voiceControllerProvider.notifier);
    _starting = true;
    try {
      if (_disposed) return;
      // Like the overlay: a hit while listening starts over.
      if (container.read(voiceControllerProvider).active) await voice.cancel();
      if (container.read(agentControllerProvider).running) {
        // Nobody takes the hit over: release the service microphone.
        await assistant.takeWakeHandoff();
        return;
      }
      final tone =
          (container.read(wakeToneProvider).value ??
              await container.read(wakeToneProvider.future)) ==
          true;
      var taken = false;
      var lost = false;
      final started = await voice.start(
        TriggerKind.wakeWord,
        takePreRoll: () async {
          taken = true;
          final pre = await takeWakePreRoll(
            platform: assistant,
            tone: tone,
            playTone: container.read(wakeConfirmToneProvider),
          );
          // Taken elsewhere meanwhile (race with the overlay fallback):
          // the microphone must not open.
          lost = pre == null;
          if (lost) await voice.cancel();
          return pre;
        },
        prepare: prepare,
      );
      if (!taken) await assistant.takeWakeHandoff();
      // Never two listeners: someone else has the hit's audio.
      if (lost && started) await voice.cancel();
    } finally {
      _starting = false;
      _check();
    }
  }

  void _check() {
    if (!_owned || _starting || _disposed) return;
    final voice = container.read(voiceControllerProvider);
    final running = container.read(agentControllerProvider).running;
    if (voice.active || voice.followUp || running) {
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }
    // A short pause between the end of listening and the start of the
    // request is no end.
    _idleTimer ??= Timer(doneDelay, _finish);
  }

  void _finish() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_owned) return;
    _owned = false;
    voiceLog('wake-chat-done');
    unawaited(_platform.chatDone());
  }

  /// The screen is gone: the service must listen again.
  void dispose() {
    if (_disposed) return;
    _finish();
    _disposed = true;
    for (final s in _subs) {
      s.close();
    }
    if (_reported ?? false) unawaited(_platform.setChatVisible(visible: false));
    _platform.onWakeHit = null;
  }
}
