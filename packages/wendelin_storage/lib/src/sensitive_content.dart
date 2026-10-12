import 'package:wendelin_core/wendelin_core.dart';

/// Thrown by `MemoryRepository.save`/`update` when the text contains
/// sensitive content (detected by core's [detectSensitiveContent]).
///
/// The message never repeats the sensitive text.
final class SensitiveContentException implements Exception {
  /// Creates the exception for [kind].
  const SensitiveContentException(this.kind);

  /// What was detected.
  final SensitiveKind kind;

  /// German, user-facing explanation ([SensitiveKind.reason]).
  String get message => kind.reason;

  @override
  String toString() => 'SensitiveContentException(${kind.name}): $message';
}

/// Throws [SensitiveContentException] if [text] contains sensitive content.
void checkNotSensitive(String text) {
  final finding = detectSensitiveContent(text);
  if (finding != null) throw SensitiveContentException(finding.kind);
}
