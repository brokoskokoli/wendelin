import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

import '../di/voice_providers.dart';
import 'voice_log.dart';

/// Speaks [text] in [language] after the answer sentences; never hangs
/// longer than [timeout] and never throws (the card shows the question
/// too, B7).
Future<void> sayBounded(
  TextToSpeech? tts,
  String text, {
  required String? language,
  required Duration timeout,
  int attempt = 0,
  String source = 'confirm',
}) async {
  if (tts == null) {
    voiceLog('confirm-prompt', {'source': source, 'tts': false});
    return;
  }
  final watch = Stopwatch()..start();
  try {
    await _say(tts, text, language).timeout(timeout);
    voiceLog('confirm-prompt', {
      'source': source,
      'attempt': attempt + 1,
      'ms': watch.elapsed,
    });
  } on TimeoutException {
    voiceLog('confirm-prompt', {'source': source, 'result': 'tts-timeout'});
    await tts.stop();
  } on Object catch (e) {
    voiceLog('confirm-prompt', {
      'source': source,
      'result': 'tts-error',
      'error': errorCode(e),
    });
  }
}

Future<void> _say(TextToSpeech tts, String text, String? language) async {
  // Let the answer sentences before the tool call finish first.
  if (tts.state == TtsState.speaking) {
    await tts.states
        .firstWhere((s) => s == TtsState.idle)
        .timeout(const Duration(seconds: 30), onTimeout: () => TtsState.idle);
    // `firstWhere` resumes inside the engine's state event; speaking from
    // there would fire a new state event while it still fires one.
    await Future<void>.delayed(Duration.zero);
  }
  await tts.speak(text, language: language);
}

/// Records one short spoken answer within [limits]; `pcm` is `null` if
/// nothing was said, the capture was aborted or the microphone did not
/// deliver within [micStartTimeout] ([reason], B7 H5).
///
/// [onAbort] gets the function that aborts the capture (and `null` when
/// it is over); [onError] gets a failure of the microphone stream.
Future<({Int16List? pcm, String reason})> captureAnswer(
  VoiceComponents components,
  AudioInput audio, {
  required EndpointConfig limits,
  required Duration micStartTimeout,
  required void Function(void Function()? abort) onAbort,
  required void Function(Object error) onError,
}) async {
  final endpointer = Endpointer(limits);
  final done = Completer<(Endpoint?, String)>();
  void end(Endpoint? e, String reason) {
    if (!done.isCompleted) done.complete((e, reason));
  }

  onAbort(() => end(null, 'aborted'));
  final watch = Stopwatch()..start();
  var frames = 0;
  StreamSubscription<Int16List>? sub;
  voiceLog('confirm-listen-start');
  try {
    components.vad.reset();
    sub = audio.start().listen(
      (frame) {
        if (done.isCompleted || frame.isEmpty) return;
        if (frames++ == 0) {
          voiceLog('confirm-mic', {'after': watch.elapsed});
        }
        final e = endpointer.add(frame, speech: components.vad.isSpeech(frame));
        if (e != null) end(e, 'endpoint');
      },
      onError: (Object error) {
        voiceLog('confirm-mic-error', {'error': errorCode(error)});
        onError(error);
        end(null, 'stream-error');
      },
      onDone: () => end(endpointer.finish(), 'stream-done'),
    );
  } on Object catch (error) {
    voiceLog('confirm-mic-error', {'error': errorCode(error)});
    end(null, 'start-error');
  }
  // The microphone must deliver soon, otherwise it did not start (H5).
  final micGuard = Timer(micStartTimeout, () {
    if (frames == 0) end(null, 'mic-timeout');
  });
  final guard = Timer(
    limits.noSpeechTimeout + limits.maxDuration,
    () => end(endpointer.finish(EndpointReason.maxDuration), 'guard'),
  );
  final (result, how) = await done.future;
  micGuard.cancel();
  guard.cancel();
  try {
    if (audio.isRunning) await audio.stop();
  } on Object catch (e) {
    voiceLog('confirm-mic-error', {'error': errorCode(e)});
  }
  unawaited(sub?.cancel());
  onAbort(null);
  final utterance = result?.kind == EndpointKind.utterance;
  final reason = result == null
      ? how
      : utterance
      ? 'utterance'
      : 'no-speech';
  voiceLog('confirm-listen-end', {
    'result': reason,
    'ms': watch.elapsed,
    'frames': frames,
  });
  return (pcm: utterance ? result!.pcm : null, reason: reason);
}
