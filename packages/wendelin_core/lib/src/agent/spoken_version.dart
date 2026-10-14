/// Whether and how the answer gets its own spoken text (K19–K21, WP55).
enum SpokenVersion {
  /// No spoken text; the written answer is read out (stage 1 + local
  /// preparation). Default.
  off,

  /// The spoken text is always used, also after foreign content (the user
  /// relies on the screen).
  always,

  /// After foreign content (web, MCP, third-party data) the written answer
  /// is read out instead of the spoken text (K20 c).
  protected,

  /// After foreign content a fresh model call checks that spoken and written
  /// text say the same; only then the spoken text is read out (fail-closed).
  checked;

  /// Whether the model is asked for a `<spoken>` block at the start.
  bool get wantsBlock => this != off;
}
