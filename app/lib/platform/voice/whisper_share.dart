import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

import 'whisper_stt.dart';

// Sharing one loaded Whisper model between Flutter engines of the process
// (ADR 0008): the app's Whisper isolate also answers requests from the
// recognizer engine (`RecognitionService`), so the model is not loaded
// twice. Engines are different isolate groups, so the messages only use
// lists, strings, `TransferableTypedData` and `SendPort`s.

const _transcribe = 'transcribe';
const _ping = 'ping';

/// Whether [message] is a request of [RemoteWhisperBackend].
bool isSharedWhisperRequest(Object? message) =>
    message is List &&
    message.isNotEmpty &&
    (message.first == _transcribe || message.first == _ping);

/// Answers a [RemoteWhisperBackend] request in the Whisper isolate:
/// `[ping, reply]` → `[pong]`, `[transcribe, audio, language, reply]` →
/// `[ok, text, language]` or `[error, message]`. Malformed requests are
/// ignored.
void answerSharedWhisper(
  List<Object?> message,
  WhisperResult Function(Float32List samples, String? language) run,
) {
  switch (message) {
    case [_ping, final SendPort reply]:
      reply.send(const ['pong']);
    case [
      _transcribe,
      final TransferableTypedData audio,
      final String? language,
      final SendPort reply,
    ]:
      try {
        final r = run(audio.materialize().asFloat32List(), language);
        reply.send(['ok', r.text, r.language, r.meanLogProb]);
      } on Object catch (e) {
        reply.send(['error', '$e']);
      }
  }
}

/// [WhisperBackend] on the Whisper isolate of another engine (found by
/// `lookupSharedWhisper`). It does not own the model: [dispose] does
/// nothing. If the owner is gone or does not answer in time, requests fail
/// with `VoiceErrorKind.unavailable` (the recognizer then loads its own
/// model); an error of the model itself is `VoiceErrorKind.failed`.
final class RemoteWhisperBackend implements WhisperBackend {
  /// Creates the client for [port] (the Whisper isolate's inbox).
  RemoteWhisperBackend(
    this.port, {
    this.timeout = const Duration(seconds: 20),
    this.pingTimeout = const Duration(seconds: 3),
  });

  /// The Whisper isolate's inbox.
  final SendPort port;

  /// Longest wait for one transcription on top of the length of the
  /// recording ([waitFor]): the shared isolate may first finish a request
  /// of its own engine. Measured on the emulator (WP19): Whisper small
  /// needs well under the audio length, so 20 s plus the audio length only
  /// runs out when the owner hangs or is gone.
  final Duration timeout;

  /// How long to wait for the text of [samples] (16 kHz).
  Duration waitFor(Float32List samples) =>
      timeout + Duration(microseconds: samples.length * 1000000 ~/ 16000);

  /// Each transcription first checks that the isolate still answers: a
  /// gone owner shows up after this time instead of after [timeout].
  final Duration pingTimeout;

  /// Whether the Whisper isolate behind [port] answers within [within]
  /// (it is busy while it transcribes for its own engine).
  static Future<bool> alive(
    SendPort port, {
    Duration within = const Duration(seconds: 3),
  }) async {
    final reply = ReceivePort();
    try {
      port.send([_ping, reply.sendPort]);
      final answer = await reply.first.timeout(within);
      return answer is List && answer.isNotEmpty && answer.first == 'pong';
    } on TimeoutException {
      return false;
    } finally {
      reply.close();
    }
  }

  @override
  Future<WhisperResult> transcribe(
    Float32List samples, {
    String? language,
  }) async {
    if (!await alive(port, within: pingTimeout)) {
      throw const VoiceException(
        VoiceErrorKind.unavailable,
        'Das Whisper-Modell der App antwortet nicht.',
      );
    }
    final reply = ReceivePort();
    try {
      port.send([
        _transcribe,
        TransferableTypedData.fromList([samples.buffer.asUint8List()]),
        language,
        reply.sendPort,
      ]);
      final Object? answer;
      try {
        answer = await reply.first.timeout(waitFor(samples));
      } on TimeoutException catch (e) {
        throw VoiceException(
          VoiceErrorKind.unavailable,
          'Whisper hat nicht rechtzeitig geantwortet.',
          cause: e,
        );
      }
      return switch (answer) {
        ['ok', final String text, final String lang, final double? lp] =>
          WhisperResult(text: text, language: lang, meanLogProb: lp),
        ['ok', final String text, final String lang] => WhisperResult(
          text: text,
          language: lang,
        ),
        ['error', final String message] => throw VoiceException(
          VoiceErrorKind.failed,
          'Die Spracherkennung ist fehlgeschlagen.',
          cause: message,
        ),
        _ => throw StateError('Whisper-Isolat: $answer'),
      };
    } finally {
      reply.close();
    }
  }

  /// Nothing to free: the model belongs to the other engine.
  @override
  Future<void> dispose() async {}
}
