import 'dart:async';

import 'package:flutter/foundation.dart';
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
/// while the overlay is open) and `close` (the overlay is being left: Dart
/// stops listening, speaking and the request, then calls [finish]).
class AssistantPlatform {
  /// Creates the bridge; `channel` is injectable for tests.
  AssistantPlatform({
    this._channel = const MethodChannel(assistantChannelName),
  });

  final MethodChannel _channel;
  final _triggers = StreamController<void>.broadcast(sync: true);
  bool _listening = false;
  Future<void> Function()? _onClose;

  void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'trigger':
          _triggers.add(null);
        case 'close':
          await _onClose?.call();
      }
    });
  }

  /// Invocations of the assistant while the overlay is open.
  Stream<void> get triggers {
    _listen();
    return _triggers.stream;
  }

  /// Runs [handler] when Android leaves the overlay (before it finishes).
  set onCloseRequested(Future<void> Function()? handler) {
    _listen();
    _onClose = handler;
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

  /// Whether Wendelin offers itself as speech recognizer to other apps
  /// while it is the default assistant (default `true`).
  Future<bool> isRecognizerOffered() async =>
      await _invoke<bool>('isRecognizerOffered') ?? true;

  /// Turns the speech recognizer for other apps on or off (takes effect
  /// only while Wendelin is the default assistant).
  Future<void> setRecognizerOffered({required bool offered}) async {
    await _invoke<void>('setRecognizerOffered', {'offered': offered});
  }

  /// Which speech recognizer Android gives other apps
  /// (`Settings.Secure` `voice_recognition_service`, ADR 0008, B12).
  /// Read only; Wendelin never changes it.
  Future<RecognitionServiceStatus> recognitionService() async =>
      RecognitionServiceStatus.fromChannel(
        await _invoke<Object?>('recognitionServiceState'),
      );

  /// Mirrors the speech settings for the recognizer service (it has no
  /// database access, ADR 0008).
  Future<void> setRecognizerConfig(RecognizerConfig config) async {
    await _invoke<void>('setRecognizerConfig', config.toArgs());
  }

  /// Closes the overlay activity.
  Future<void> finish() async {
    await _invoke<void>('finish');
  }

  Future<T?> _invoke<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
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

/// Whom Android asks when another app wants speech recognition.
enum RecognitionServiceState {
  /// Wendelin (`app.wendelin/.WendelinRecognitionService`), and its
  /// service may answer.
  active,

  /// Android names Wendelin, but its service is off (no assistant role or
  /// not offered): other apps get errors.
  inactive,

  /// Another service; it cannot be changed on this device.
  other,

  /// Not readable (no value, no permission, no self-test possible).
  unknown,
}

/// Current system speech recognizer with the name of its app.
@immutable
final class RecognitionServiceStatus {
  /// Creates the status.
  const RecognitionServiceStatus(this.state, {this.appName});

  /// Reads the channel answer `{state, appName}`; anything else is
  /// [RecognitionServiceState.unknown].
  factory RecognitionServiceStatus.fromChannel(Object? value) {
    if (value is! Map) return unknown;
    final state = switch (value['state']) {
      'active' => RecognitionServiceState.active,
      'inactive' => RecognitionServiceState.inactive,
      'other' => RecognitionServiceState.other,
      _ => RecognitionServiceState.unknown,
    };
    final name = value['appName'];
    return RecognitionServiceStatus(
      state,
      appName: state == RecognitionServiceState.other && name is String
          ? name.trim().isEmpty
                ? null
                : name.trim()
          : null,
    );
  }

  /// Nothing known.
  static const unknown = RecognitionServiceStatus(
    RecognitionServiceState.unknown,
  );

  /// State.
  final RecognitionServiceState state;

  /// App name of the other service (only with
  /// [RecognitionServiceState.other], if Android shows it).
  final String? appName;

  @override
  bool operator ==(Object other) =>
      other is RecognitionServiceStatus &&
      other.state == state &&
      other.appName == appName;

  @override
  int get hashCode => Object.hash(state, appName);

  @override
  String toString() => 'RecognitionServiceStatus(${state.name}, $appName)';
}

/// Speech settings the system recognizer uses (mirror of Einstellungen →
/// Sprache): Whisper model, language (`null` = detect), Silero threshold,
/// minimum speech duration.
@immutable
final class RecognizerConfig {
  /// Creates the configuration.
  const RecognizerConfig({
    required this.model,
    required this.language,
    required this.vadThreshold,
    required this.minSpeechMs,
  });

  /// Whisper model id.
  final String model;

  /// Fixed language or `null` (detect).
  final String? language;

  /// Silero threshold.
  final double vadThreshold;

  /// Minimum speech duration (ms).
  final int minSpeechMs;

  /// Channel arguments (`language` `''` = detect).
  Map<String, Object> toArgs() => {
    'model': model,
    'language': language ?? '',
    'vadThreshold': vadThreshold,
    'minSpeechMs': minSpeechMs,
  };

  @override
  bool operator ==(Object other) =>
      other is RecognizerConfig &&
      other.model == model &&
      other.language == language &&
      other.vadThreshold == vadThreshold &&
      other.minSpeechMs == minSpeechMs;

  @override
  int get hashCode => Object.hash(model, language, vadThreshold, minSpeechMs);
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
