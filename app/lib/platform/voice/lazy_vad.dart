import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

/// A [VoiceActivityDetector] that opens its native detector on first use
/// and gives it back on [release] (the overlay engine ends without ever
/// disposing its providers, so a detector that stays open would leak once
/// per overlay, B14/WP143). The next frame after [release] opens it again.
final class LazyVoiceActivityDetector implements VoiceActivityDetector {
  /// [open] creates the native detector, [close] frees it.
  LazyVoiceActivityDetector({
    required this.threshold,
    required this._open,
    required this._close,
  });

  @override
  final double threshold;

  final VoiceActivityDetector Function() _open;
  final void Function(VoiceActivityDetector) _close;
  VoiceActivityDetector? _inner;
  bool _disposed = false;

  /// Whether the native detector is open (tests, logs).
  bool get isOpen => _inner != null;

  /// Opens the native detector now (prewarm), so the first frame does not.
  void warm() {
    if (!_disposed) _inner ??= _open();
  }

  @override
  double speechProbability(Int16List frame) {
    if (_disposed) return 0;
    return (_inner ??= _open()).speechProbability(frame);
  }

  @override
  void reset() => _inner?.reset();

  /// Frees the native detector now; a later frame opens it again.
  void release() {
    final inner = _inner;
    _inner = null;
    if (inner != null) _close(inner);
  }

  /// Frees it for good (provider end).
  void dispose() {
    _disposed = true;
    release();
  }
}
