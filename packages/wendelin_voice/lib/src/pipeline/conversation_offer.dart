/// Whether continued listening would have helped after a spoken answer
/// (K23 d, M4 decision 2): the one-time question „Soll ich nach meinen
/// Antworten standardmäßig weiter zuhören?“ is only worth asking then.
///
/// That is the case when
/// - the answer ends with a question to the user ([lastSentence] ends in
///   `?`), or
/// - the user asked by voice again shortly after the previous spoken
///   answer ([sinceLastAnswer] within [repeatWindow]): they tap the
///   microphone again and again.
bool followUpUseful({
  String? lastSentence,
  Duration? sinceLastAnswer,
  Duration repeatWindow = const Duration(minutes: 2),
}) {
  final text = lastSentence?.trim() ?? '';
  if (text.endsWith('?') || text.endsWith('？')) return true;
  return sinceLastAnswer != null && sinceLastAnswer <= repeatWindow;
}
