import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Name of the platform channel of the system assistant (Kotlin side:
/// `AssistantChannel.kt`).
const assistantChannelName = 'app.wendelin/assistant';

/// Bridge to the system assistant (overridden in tests).
final assistantPlatformProvider = Provider<AssistantPlatform>((ref) {
  final platform = AssistantPlatform();
  ref.onDispose(platform.dispose);
  return platform;
});

/// The app as Android system assistant (`VoiceInteractionService`):
/// status and settings for the main app, lock state, unlock request and
/// closing for the overlay.
///
/// Calls from Kotlin to Dart: `trigger` (the assistant was invoked again
/// while the overlay is open).
class AssistantPlatform {
  /// Creates the bridge; `channel` is injectable for tests.
  AssistantPlatform({
    this._channel = const MethodChannel(assistantChannelName),
  });

  final MethodChannel _channel;
  final _triggers = StreamController<void>.broadcast(sync: true);
  bool _listening = false;

  /// Invocations of the assistant while the overlay is open.
  Stream<void> get triggers {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'trigger') _triggers.add(null);
      });
    }
    return _triggers.stream;
  }

  /// Whether Wendelin is the default assistant (role `ASSISTANT` or the
  /// secure setting `assistant`). `false` where unknown.
  Future<bool> isDefaultAssistant() async =>
      await _invoke<bool>('isDefaultAssistant') ?? false;

  /// Opens the system settings where the default assistant is chosen
  /// (`Settings.ACTION_VOICE_INPUT_SETTINGS`, otherwise the default apps).
  /// Returns whether a settings page could be opened.
  Future<bool> openAssistantSettings() async =>
      await _invoke<bool>('openAssistantSettings') ?? false;

  /// Whether the device shows the lock screen right now.
  Future<bool> isLocked() async => await _invoke<bool>('isLocked') ?? false;

  /// Asks the user to unlock (keyguard); `true` once unlocked, `false` if
  /// cancelled or impossible.
  Future<bool> requestUnlock() async =>
      await _invoke<bool>('requestUnlock') ?? false;

  /// Closes the overlay activity.
  Future<void> finish() async {
    await _invoke<void>('finish');
  }

  Future<T?> _invoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Stops listening for [triggers].
  void dispose() {
    if (_listening) _channel.setMethodCallHandler(null);
    unawaited(_triggers.close());
  }
}

/// [TriggerSource] of the system assistant: fires
/// `TriggerKind.assistant` when the overlay starts ([fire]) and whenever
/// the assistant is invoked again while it is open.
final class AssistantTriggerSource implements TriggerSource {
  /// Creates the source on [platform].
  AssistantTriggerSource(this.platform, {required this.clock}) {
    _sub = platform.triggers.listen((_) => fire());
  }

  /// The assistant bridge.
  final AssistantPlatform platform;

  /// Time of the triggers.
  final Clock clock;

  final _controller = StreamController<TriggerEvent>.broadcast(sync: true);
  late final StreamSubscription<void> _sub;

  @override
  Stream<TriggerEvent> get triggers => _controller.stream;

  /// Reports an invocation of the assistant now.
  void fire() => _controller.add(
    TriggerEvent(source: TriggerKind.assistant, at: clock.now()),
  );

  /// Stops listening.
  Future<void> dispose() async {
    await _sub.cancel();
    await _controller.close();
  }
}
