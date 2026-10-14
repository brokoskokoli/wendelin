/// Why a conversation of the conversation mode ended (diagnostics code
/// `conv-exit reason=<name>`, exactly one per conversation).
enum ConversationEndReason {
  /// The follow-up window passed without speech (or nothing was understood).
  silence,

  /// A stop word („Stopp“) – spoken or as barge-in keyword.
  stopWord,

  /// A closing phrase („Danke“, „Das war’s“).
  closingPhrase,

  /// Tapped.
  tap,

  /// Aborted by a new trigger or by disposing the pipeline.
  cancelled,

  /// A confirmation card is open (the yes/no logic takes over).
  confirmation,

  /// `VoicePipelineConfig.maxFollowUps` reached.
  maxFollowUps,

  /// A component or the agent failed.
  error,
}

/// Lower-case words of [text] without punctuation; apostrophes are dropped
/// („das war’s“ → `das wars`).
List<String> normalizedWords(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[\'’`´]'), '')
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((w) => w.isNotEmpty)
    .toList();

/// Whether [text] consists only of [phrases], one or several in a row
/// („Danke“, „Danke, das war’s“). Anything else makes it a new question.
bool isClosingPhrase(String text, Set<String> phrases) {
  final words = normalizedWords(text);
  if (words.isEmpty) return false;
  final known = [for (final p in phrases) normalizedWords(p)];
  var i = 0;
  while (i < words.length) {
    final hit = known.where(
      (p) =>
          p.isNotEmpty &&
          i + p.length <= words.length &&
          [for (var k = 0; k < p.length; k++) words[i + k] == p[k]]
              .every((b) => b),
    );
    if (hit.isEmpty) return false;
    i += hit.map((p) => p.length).reduce((a, b) => a > b ? a : b);
  }
  return true;
}

/// Whether [text] is a stop command: only [stopWords], [stopPhrases] and
/// [fillerWords], at least one stop word or phrase.
bool isStopCommand(
  String text, {
  required Set<String> stopWords,
  required Set<String> fillerWords,
  required Set<String> stopPhrases,
}) {
  final words = text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty)
      .toList();
  // Words covered by a stop phrase count as stop words.
  final stop = [for (final w in words) stopWords.contains(w)];
  for (final phrase in stopPhrases) {
    final p = phrase.split(' ');
    for (var i = 0; i + p.length <= words.length; i++) {
      var match = true;
      for (var k = 0; k < p.length && match; k++) {
        match = words[i + k] == p[k];
      }
      if (match) stop.fillRange(i, i + p.length, true);
    }
  }
  var any = false;
  for (var i = 0; i < words.length; i++) {
    if (stop[i]) {
      any = true;
    } else if (!fillerWords.contains(words[i])) {
      return false;
    }
  }
  return any;
}
