import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import '../speaker/speaker_embedder.dart' show speakerSampleRate;
import '../speaker/speaker_match.dart';

/// Recognition of who spoke an utterance for one pipeline (WP92a, WP160):
/// timeout, failure handling and the diagnostic line, apart from the
/// pipeline's state machine.
final class SpeakerIdentification {
  const SpeakerIdentification({
    required this.recognizer,
    required this.clock,
    this.diagnostics,
  });

  /// `null` = recognition off.
  final SpeakerRecognizer? recognizer;
  final Clock clock;
  final void Function(String event)? diagnostics;

  /// How long a request waits for the recognition at most; a hanging
  /// recognizer must never hang the request („unbekannt“ instead).
  static const timeout = Duration(seconds: 3);

  /// Recognition of who spoke [pcm], started before the transcription so
  /// both run in parallel. `null` = recognition off; never throws.
  Future<SpeakerMatch?> identify(Int16List pcm) async {
    final recognizer = this.recognizer;
    final started = clock.now();
    final audioMs = pcm.length * 1000 ~/ speakerSampleRate;
    String line(String result, [String? reason, SpeakerMatch? m]) =>
        speakerLogLine(
          result: result,
          reason: reason,
          match: m,
          audioMs: audioMs,
          ms: clock.now().difference(started).inMilliseconds,
        );
    if (recognizer == null) {
      diagnostics?.call(line('off'));
      return null;
    }
    try {
      final m = await recognizer.identify(pcm).timeout(timeout);
      diagnostics?.call(
        line(m.isKnown ? 'known' : 'unknown', m.reason?.name, m),
      );
      return m;
    } on TimeoutException {
      diagnostics?.call('speaker-timeout');
      diagnostics?.call(line('unknown', 'timeout'));
      return const SpeakerMatch.unknown(SpeakerUnknownReason.failed);
    } on Object {
      diagnostics?.call('speaker-failed');
      diagnostics?.call(line('unknown', 'failed'));
      return const SpeakerMatch.unknown(SpeakerUnknownReason.failed);
    }
  }
}
