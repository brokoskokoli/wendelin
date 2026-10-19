import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

import '../wake/utterance_capture.dart';

/// One enrollment sentence: up to 6 s wait, up to 10 s speech, at least
/// 1.2 s (WP92a).
UtteranceCapture newSentenceCapture() => UtteranceCapture(
  maxWait: 6 * AudioInput.sampleRate,
  maxSpeech: 10 * AudioInput.sampleRate,
  minSpeech: SpeakerIdentifier.minEnrollAudioSamples,
);

/// Records one sentence from [audio]; `null` if the stream ended without a
/// result (stopped). The audio only lives in memory; [onLevel] gets the
/// level (0–1).
Future<Utterance?> recordSentence(
  AudioInput audio, {
  UtteranceCapture? capture,
  void Function(double level)? onLevel,
}) async {
  final c = capture ?? newSentenceCapture();
  final done = Completer<Utterance?>();
  final sub = audio.start().listen(
    (Int16List frame) {
      final r = c.feed(frame);
      onLevel?.call(c.level);
      if (r != null && !done.isCompleted) done.complete(r);
    },
    onError: (Object e, StackTrace s) {
      if (!done.isCompleted) done.completeError(e, s);
    },
    onDone: () {
      if (!done.isCompleted) done.complete(null);
    },
  );
  try {
    return await done.future;
  } finally {
    await sub.cancel();
    await audio.stop();
  }
}
