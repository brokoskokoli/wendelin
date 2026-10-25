import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'channels.dart';
import 'voice/pcm.dart';

export 'channels.dart' show assistantChannelName;

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
/// stops listening, speaking and the request, then calls [releaseHost]).
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

  /// Whether a wake word hit waits for the overlay (WP50). Does not take it.
  Future<bool> hasWakeHandoff() async =>
      await _invoke<bool>('hasWakeHandoff') ?? false;

  /// The audio of the wake word hit that opened the overlay (16 kHz mono
  /// PCM, from the end of the wake word on whatever was said until now,
  /// gap-free), once; `null` if the overlay was opened by a button (WP50,
  /// WP68). Taking it ends the service's recording: the caller opens its own
  /// microphone right after.
  ///
  /// With [keepOpen] (WP146) the service keeps recording after the take until
  /// [finishWakeHandoff]: the caller opens its microphone, waits for its first
  /// frame and only then finishes, so there is no hole between the two.
  Future<WakeHandoffAudio?> takeWakeHandoff({bool keepOpen = false}) async {
    final raw = await _invoke<Map<Object?, Object?>>(
      'takeWakeHandoff',
      keepOpen ? {'keepOpen': true} : null,
    );
    if (raw == null) return null;
    final bytes = raw['pcm'];
    if (bytes is! Uint8List) return null;
    return WakeHandoffAudio(
      pcm: PcmBytesDecoder().convert(bytes),
      wakeEnd: (raw['wakeEnd'] as num?)?.toInt(),
      capturedMs: (raw['capturedMs'] as num?)?.toInt() ?? 0,
      lastSampleAtMs: (raw['lastSampleAt'] as num?)?.toInt(),
    );
  }

  /// Tells the wake-word service whether this app records or is about to (a
  /// voice request, its answer, a follow-up window, WP146): the service keeps
  /// its microphone closed meanwhile and for a short time after.
  Future<void> appVoiceActive({required bool active}) async {
    await _invoke<void>('appVoiceActive', {'active': active});
  }

  /// Ends a handoff taken with `keepOpen` (WP146): the service stops its
  /// microphone and returns what it recorded since the take, with the time of
  /// its last sample; `null` if nothing was kept open.
  Future<WakeHandoffAudio?> finishWakeHandoff() async {
    final raw = await _invoke<Map<Object?, Object?>>('finishWakeHandoff');
    if (raw == null) return null;
    final bytes = raw['pcm'];
    if (bytes is! Uint8List) return null;
    return WakeHandoffAudio(
      pcm: PcmBytesDecoder().convert(bytes),
      capturedMs: (raw['capturedMs'] as num?)?.toInt() ?? 0,
      lastSampleAtMs: (raw['lastSampleAt'] as num?)?.toInt(),
    );
  }

  /// The overlay is closing (WP145): Android finishes the activity at once
  /// (the wake word listens again, a new invocation opens a new overlay) and
  /// keeps this engine alive without a window until [teardownDone] or a
  /// timeout, so a native free that takes longer (a Whisper model still
  /// loading) runs to its end. `false` if the host cannot do that; then the
  /// caller ends with [finish].
  Future<bool> releaseHost() async =>
      await _invoke<bool>('releaseHost') ?? false;

  /// The teardown after [releaseHost] is over: Android destroys the engine.
  Future<void> teardownDone() async => _invoke<void>('teardownDone');

  /// Closes the overlay activity.
  ///
  /// `false` if the station refused (device still locked) or the call failed; the overlay
  /// always closes.
  Future<bool> finish() async => await _invoke<bool>('finish') ?? false;

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

/// The audio a wake word hit leaves for the overlay (WP50, WP68).
final class WakeHandoffAudio {
  /// Creates the handoff.
  const WakeHandoffAudio({
    required this.pcm,
    this.wakeEnd,
    this.capturedMs = 0,
    this.lastSampleAtMs,
  });

  /// 16 kHz mono PCM: pre-roll up to the confirmation and what the service
  /// recorded until it was taken, without gap or overlap.
  final Int16List pcm;

  /// Sample in [pcm] where the wake word ends; `null` if unknown.
  final int? wakeEnd;

  /// How much of [pcm] the service recorded after the confirmation.
  final int capturedMs;

  /// Wall clock (ms since epoch) of the last sample the service recorded.
  final int? lastSampleAtMs;
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
/// the assistant is invoked again while it is open. A start by the wake
/// word service fires `TriggerKind.wakeWord`.
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

  /// Reports an invocation of the assistant now; with [wake] it was the wake
  /// word (its audio is taken by the recording, WP68).
  void fire({bool wake = false}) => _controller.add(
    TriggerEvent(
      source: wake ? TriggerKind.wakeWord : TriggerKind.assistant,
      at: clock.now(),
    ),
  );

  /// Stops listening.
  Future<void> dispose() async {
    await _sub.cancel();
    await _controller.close();
  }
}
