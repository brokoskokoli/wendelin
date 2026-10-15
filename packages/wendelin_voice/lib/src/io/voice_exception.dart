/// What went wrong in a voice component.
enum VoiceErrorKind {
  /// The microphone permission is missing.
  permissionDenied,

  /// The engine or device is not available (e.g. no microphone, no TTS).
  unavailable,

  /// A required model is not downloaded.
  modelMissing,

  /// The requested language is not supported by the engine.
  unsupportedLanguage,

  /// The microphone is still in use (a recording is already running).
  busy,

  /// Anything else (engine crash, I/O error).
  failed,
}

/// Error of an audio, VAD, STT or TTS implementation.
///
/// [message] is German, secret-free and may be shown to the user.
final class VoiceException implements Exception {
  /// Creates the exception.
  const VoiceException(this.kind, this.message, {this.cause});

  /// Kind of failure.
  final VoiceErrorKind kind;

  /// German user-facing message.
  final String message;

  /// Underlying error, if any.
  final Object? cause;

  @override
  String toString() => 'VoiceException(${kind.name}, $message)';
}
