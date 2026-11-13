part of 'voice_pipeline.dart';

/// Answers a request given as text (WP114).
extension VoicePipelineText on VoicePipeline {
  /// Answers [text] like a recognized request, without listening: the agent
  /// runs and the answer is spoken (the request that waited for the unlock).
  /// Returns `false` if a request is already running.
  bool answerText(String text, {String? language}) {
    if (_disposed || _state != VoiceState.idle) return false;
    final gen = ++_gen;
    _session = _answerOnly(gen, Transcript(text: text, language: language));
    return true;
  }

  Future<void> _answerOnly(int gen, Transcript transcript) async {
    _setState(VoiceState.thinking);
    await _answer(gen, transcript);
    _finish(gen);
  }

  Future<Transcript?> _transcribe(int gen, Int16List pcm) async {
    _setState(VoiceState.transcribing);
    try {
      final who = SpeakerIdentification(
        recognizer: speaker,
        clock: clock,
        diagnostics: diagnostics,
      ).identify(pcm);
      final text = await stt.transcribe(pcm, language: config.language);
      final match = await who;
      if (gen != _gen) return null;
      final t = match == null ? text : text.withSpeaker(match);
      _emit(VoiceTranscribed(t));
      return t;
    } on Object catch (error) {
      if (gen == _gen) _emit(VoiceError(VoiceState.transcribing, error));
      return null;
    }
  }

  Future<void> _nothingUnderstood(
    int gen,
    EndpointReason? reason, {
    String? language,
  }) async {
    _emit(VoiceNothingUnderstood(reason));
    if (!config.speakNothingUnderstood) return;
    final lang = language ?? config.language;
    await _speakOnly(gen, [VoiceTexts.of(lang).nothingUnderstood], lang);
  }

  /// Speaks [sentences] outside of an answer (e.g. „nichts verstanden“).
  Future<void> _speakOnly(int gen, List<String> sentences, String? lang) async {
    final queue = await _newQueue(gen, lang);
    if (queue == null || gen != _gen) return;
    queue.addAll(sentences);
    await queue.whenIdle;
    if (_queue == queue) _queue = null;
  }
}
