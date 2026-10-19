// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'voice_controller.dart';

/// Spoken confirmation of agent questions (B5, B7, H2, H4).
extension _VoiceConfirmation on VoiceController {
  void _onPending(PendingQuestion? next) {
    final current = _confirming;
    if (current != null && !identical(current, next)) {
      // Answered by tap, or the run ended: stop listening for the answer.
      _abortCapture?.call();
    }
    if (next == null || next.answered) {
      _queued = null;
      if (state.tapOnly) state = state.copyWith(tapOnly: false);
      return;
    }
    if (state.tapOnly) state = state.copyWith(tapOnly: false);
    if (identical(current, next)) return;
    if (current != null) {
      // A new question while the previous one still winds down: it is
      // asked as soon as that one is over (B7, H4).
      _queued = next;
      return;
    }
    _maybeConfirm(next);
  }

  /// Whether the running agent request is a voice request.
  bool get _voiceRequest {
    final pipeline = _pipeline;
    return _voiceRun || (pipeline != null && pipeline.state != VoiceState.idle);
  }

  void _maybeConfirm(PendingQuestion question) {
    if (!_voiceRequest) {
      // Typed request: the card answers by tap; no line per question.
      return;
    }
    unawaited(_confirmByVoice(question));
  }

  Future<void> _confirmByVoice(PendingQuestion question) async {
    final cancels = _cancels;
    final outgoing = outgoingPreviewOf(question);
    String? closed() {
      if (cancels != _cancels) return 'not-open(cancelled)';
      final pending = ref.read(agentControllerProvider).pending;
      if (question.answered) return 'not-open(answered)';
      if (!identical(pending, question)) return 'not-open(replaced)';
      return null;
    }

    // Exactly one exit line per question: `confirm-exit reason=…`.
    var reason = 'unknown';
    var byTap = false;
    _confirming = question;
    final watch = Stopwatch()..start();
    voiceLog('confirm-start', {
      'phase': _pipeline?.state,
      'strict': strictAnswer(question),
    });
    try {
      final components = _components;
      final audio = _audio;
      if (components == null || audio == null) {
        reason = 'no-components';
        byTap = true;
        return;
      }
      if (audio.isRunning) {
        // The previous recording has not stopped yet (B7, H2): stop it.
        voiceLog('confirm-wait', {'reason': 'audio-running'});
        try {
          await audio.stop().timeout(const Duration(seconds: 2));
        } on Object catch (e) {
          voiceLog('confirm-wait-failed', {'error': errorCode(e)});
        }
        if (audio.isRunning) {
          reason = 'audio-running';
          byTap = true;
          return;
        }
      }
      TextToSpeech? tts;
      try {
        tts = await components.textToSpeech(_language);
      } on Object catch (e) {
        voiceLog('confirm-tts-error', {'error': errorCode(e)});
      }
      _promptTts = tts;
      for (var attempt = 0; attempt < 2; attempt++) {
        if (closed() case final r?) {
          reason = r;
          return;
        }
        final prompt = attempt == 0
            ? confirmationPrompt(question, _language)
            : repeatPrompt(_language, outgoing: outgoing?.kind);
        await sayBounded(
          tts,
          prompt,
          language: _language,
          timeout: VoiceController.promptTimeout,
          attempt: attempt,
        );
        if (closed() case final r?) {
          reason = r;
          return;
        }
        state = state.copyWith(awaitingAnswer: true, levels: const []);
        final capture = await captureAnswer(
          components,
          audio,
          limits: VoiceController.answerEndpoint,
          micStartTimeout: VoiceController.micStartTimeout,
          onAbort: (abort) => _abortCapture = abort,
          onError: (e) =>
              state = state.copyWith(error: voiceErrorText(uiTexts(ref), e)),
        );
        state = state.copyWith(awaitingAnswer: false);
        if (closed() case final r?) {
          reason = r;
          return;
        }
        final pcm = capture.pcm;
        if (pcm == null) {
          reason = 'capture-null(${capture.reason})';
          byTap = true;
          return;
        }
        final Transcript transcript;
        try {
          transcript = await components.stt.transcribe(
            pcm,
            language: components.config.language,
          );
        } on Object catch (e) {
          voiceLog('confirm-stt-error', {'error': errorCode(e)});
          state = state.copyWith(error: voiceErrorText(uiTexts(ref), e));
          reason = 'stt-error';
          byTap = true;
          return;
        }
        if (closed() case final r?) {
          reason = r;
          return;
        }
        final answer = VoiceController.recognizer.parse(
          transcript.text,
          strict: strictAnswer(question),
          extraYes: switch (outgoing?.kind) {
            OutgoingKind.sms => YesNoRecognizer.smsYesWords,
            OutgoingKind.call => YesNoRecognizer.callYesWords,
            null => const {},
          },
        );
        if (answer == YesNo.yes &&
            outgoing != null &&
            ref
                .read(smsDraftEditsProvider)
                .isEdited(outgoing.number, outgoing.text)) {
          // The user changed the text after it was read aloud: a spoken yes
          // would confirm text nobody heard. Only a tap sends it.
          reason = 'edited';
          byTap = true;
          return;
        }
        if (answer != null) {
          reason = 'answered(${answer.name})';
          _agent.answer(approved: answer == YesNo.yes);
          return;
        }
        voiceLog('confirm-unclear', {'attempt': attempt + 1});
      }
      reason = 'unclear';
      byTap = true;
    } on Object catch (e) {
      reason = 'error(${errorCode(e)})';
      byTap = true;
      state = state.copyWith(error: voiceErrorText(uiTexts(ref), e));
    } finally {
      _confirming = null;
      _abortCapture = null;
      final tts = _promptTts;
      _promptTts = null;
      if (state.awaitingAnswer) state = state.copyWith(awaitingAnswer: false);
      voiceLog('confirm-exit', {
        'reason': reason,
        'tap': byTap,
        'ms': watch.elapsed,
      });
      if (byTap && closed() == null) await _answerByTap(tts);
      _askQueued();
    }
  }

  /// The spoken answer did not work: the card says „Antworte per Tipp“
  /// and Wendelin says it once (B7).
  Future<void> _answerByTap(TextToSpeech? tts) async {
    state = state.copyWith(tapOnly: true);
    if (tts == null) return;
    _promptTts = tts;
    try {
      await sayBounded(
        tts,
        tapAnswerPrompt(_language),
        language: _language,
        timeout: VoiceController.promptTimeout,
        source: 'tap-hint',
      );
    } finally {
      if (identical(_promptTts, tts)) _promptTts = null;
    }
  }

  void _askQueued() {
    final next = _queued;
    _queued = null;
    if (next == null || next.answered) return;
    if (!identical(ref.read(agentControllerProvider).pending, next)) return;
    _maybeConfirm(next);
  }
}
