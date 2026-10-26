/// Security level of a tool or a device (WP154, ADR 0022). The user chooses
/// it per tool (and per Home Assistant device); the default is the
/// recommendation of the tool.
enum SecurityLevel {
  /// Always, also locked and without a recognized voice.
  a,

  /// With a recognized voice (also locked) or unlocked.
  b,

  /// Only unlocked.
  c,

  /// Unlocked and a confirmation on the display.
  d;

  /// The level stored as [raw] (`a`..`d`), `null` for anything else.
  static SecurityLevel? parse(String? raw) {
    for (final l in values) {
      if (l.name == raw) return l;
    }
    return null;
  }

  /// The level that counts for a stored text: [raw] `null` = the user chose
  /// nothing, so [fallback] (the default). Anything stored that is not
  /// `a`..`d` is **D** (fail-closed).
  static SecurityLevel effective(String? raw, SecurityLevel fallback) =>
      raw == null ? fallback : (parse(raw) ?? d);
}

/// Outcome of the policy for one call.
enum LevelAccess {
  /// Runs without a question.
  allowed,

  /// Runs after the confirmation on the display.
  confirm,

  /// The device has to be unlocked first.
  unlock,
}

/// The table: level × locked × recognized voice → [LevelAccess]. A missing
/// level is D (fail-closed).
///
/// | Level | unlocked | locked, voice recognized | locked, other voice |
/// |---|---|---|---|
/// | A | allowed | allowed | allowed |
/// | B | allowed | allowed | unlock |
/// | C | allowed | unlock | unlock |
/// | D | confirm | unlock | unlock |
LevelAccess levelAccess(
  SecurityLevel? level, {
  bool locked = false,
  bool speakerRecognized = false,
}) {
  switch (level ?? SecurityLevel.d) {
    case SecurityLevel.a:
      return LevelAccess.allowed;
    case SecurityLevel.b:
      return !locked || speakerRecognized
          ? LevelAccess.allowed
          : LevelAccess.unlock;
    case SecurityLevel.c:
      return locked ? LevelAccess.unlock : LevelAccess.allowed;
    case SecurityLevel.d:
      return locked ? LevelAccess.unlock : LevelAccess.confirm;
  }
}
