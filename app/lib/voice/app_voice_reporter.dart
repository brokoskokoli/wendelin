import 'dart:async';

import '../platform/assistant_platform.dart';
import 'voice_ui_state.dart';

/// Tells the platform whether the app records or is about to (request,
/// answer, follow-up window), so the wake word service keeps its microphone
/// closed meanwhile (WP146). A short `false` between preparing and listening
/// is covered by the service's quiet time.
final class AppVoiceReporter {
  /// Creates the reporter for [_platform].
  AppVoiceReporter(this._platform);

  final AssistantPlatform _platform;
  bool _busy = false;
  Timer? _beat;

  /// The service forgets an "active" report after a cap (fail-safe against a
  /// lost end); while the app really is busy it repeats it.
  static const heartbeat = Duration(seconds: 60);

  /// The state changed: reports a change of the busy flag.
  void update(VoiceUiState next) {
    final busy = next.active || next.followUp;
    if (busy == _busy) return;
    _busy = busy;
    _beat?.cancel();
    _beat = busy
        ? Timer.periodic(
            heartbeat,
            (_) => unawaited(_platform.appVoiceActive(active: true)),
          )
        : null;
    unawaited(_platform.appVoiceActive(active: busy));
  }

  /// The controller ends: the service may listen again.
  void dispose() {
    _beat?.cancel();
    _beat = null;
    if (_busy) unawaited(_platform.appVoiceActive(active: false));
    _busy = false;
  }
}
