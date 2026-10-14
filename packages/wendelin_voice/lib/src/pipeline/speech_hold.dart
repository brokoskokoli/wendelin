/// Holds the written text of a segment back from the speech output while
/// the check of its spoken text is pending (WP55, `SpokenVersion.checked`).
/// Internal to `wendelin_voice`, not exported.
library;

/// Collects the text deltas between `AgentSpokenHold` and the verdict.
///
/// Fail-closed: whatever ends the hold without an accepted spoken text
/// (rejection, tool call, end of the answer) releases the written text, so
/// the user hears the visible answer, never nothing and never unchecked
/// spoken text.
final class SpeechHold {
  bool _active = false;
  final List<String> _held = [];

  /// Starts holding (the spoken text is being checked).
  void start() => _active = true;

  /// Takes [delta] if holding; `false` = the caller speaks it as usual.
  bool take(String delta) {
    if (!_active) return false;
    _held.add(delta);
    return true;
  }

  /// Ends the hold and returns the held deltas to speak (written fallback).
  List<String> release() {
    _active = false;
    final out = List<String>.of(_held);
    _held.clear();
    return out;
  }

  /// Ends the hold and forgets the held text (accepted spoken text, reset).
  void drop() {
    _active = false;
    _held.clear();
  }
}
