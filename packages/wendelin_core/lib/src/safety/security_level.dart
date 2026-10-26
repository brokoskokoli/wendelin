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

/// Who asks and in which device state (WP154 L2, ADR 0022): the input of
/// [levelAccess] as one value that travels with a request. WP157 adds more
/// fields (e.g. the speaker) without touching every call site.
///
/// Fail-closed: the default is the **unlocked** device only where a request
/// comes from the typed or spoken app itself; everything that runs while the
/// device is locked names it explicitly ([lockedUnknownVoice]).
final class AccessContext {
  /// Creates the context.
  const AccessContext({this.locked = false, this.speakerRecognized = false});

  /// The device is unlocked (typed or spoken request in the app).
  static const unlocked = AccessContext();

  /// The device is locked and the voice is not recognized (until WP92 L3).
  static const lockedUnknownVoice = AccessContext(locked: true);

  /// Whether the device is locked.
  final bool locked;

  /// Whether the voice belongs to a recognized person (only meaningful while
  /// locked, level B).
  final bool speakerRecognized;

  /// The table [levelAccess] for [level] in this context.
  LevelAccess of(SecurityLevel? level) =>
      levelAccess(level, locked: locked, speakerRecognized: speakerRecognized);

  @override
  bool operator ==(Object other) =>
      other is AccessContext &&
      other.locked == locked &&
      other.speakerRecognized == speakerRecognized;

  @override
  int get hashCode => Object.hash(locked, speakerRecognized);

  @override
  String toString() =>
      'AccessContext(locked: $locked, speakerRecognized: $speakerRecognized)';
}

/// Optional capability of a `Tool`: the tool's standard level when the user
/// chose none, instead of the one of its risk (`RiskPolicy.defaultLevelOf`).
/// Used where the recommendation differs from `read`/`write` = C (e.g. the
/// flashlight: A, because it reads and sends nothing and affects nobody).
abstract interface class DefaultLevelTool {
  /// The standard level of this tool.
  SecurityLevel get defaultLevel;
}

/// Optional capability of a `Tool`: the tool decides the level itself, per
/// device (Home Assistant `ha__call`, ADR 0022). While locked the policy
/// leaves the decision to the tool, which asks `ToolContext.access`; the tool
/// must refuse ("Entsperren nötig") whatever it does not allow. Without a
/// level a locked call of any other tool is refused.
abstract interface class LevelPerDeviceTool {}
