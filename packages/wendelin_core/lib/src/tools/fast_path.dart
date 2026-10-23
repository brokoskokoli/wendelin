/// A command recognized without a model (WP135 D).
///
/// [tool] and [arguments] are exactly what the model would have sent: the
/// agent runs them through the same tool path (executor, history, undo,
/// audit, fixed confirmation sentence).
final class FastPathCall {
  /// Creates the call.
  const FastPathCall({required this.tool, required this.arguments});

  /// Tool name, e.g. `ha__call`.
  final String tool;

  /// Tool arguments.
  final Map<String, Object?> arguments;

  @override
  String toString() => 'FastPathCall($tool)';
}

/// Recognizes simple, unambiguous requests locally so that no model call is
/// needed (WP135 D). Implemented by an integration, run by the agent before
/// the first model call.
///
/// Contract: [match] is as strict as `matchLockedCommand` — every word of
/// the utterance must be known, exactly one action, exactly one target; in
/// doubt it returns `null` and the model answers. It never throws (the
/// agent treats an exception like `null`) and it never names a tool that
/// needs a confirmation or is not safe without one.
abstract interface class FastPath {
  /// The call for [text] in [language] (BCP 47 tag, `null` = unknown),
  /// or `null` if the request is not simple and safe enough.
  Future<FastPathCall?> match(String text, {required String? language});
}
