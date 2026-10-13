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
        reply.send(['ok', r.text, r.language]);
      } on Object catch (e) {
        reply.send(['error', '$e']);
      }
  }
}

/// [WhisperBackend] on the Whisper isolate of another engine (found by
/// `lookupSharedWhisper`). It does not own the model: [dispose] does
/// nothing, and if the owner is gone, requests time out.
final class RemoteWhisperBackend implements WhisperBackend {
  /// Creates the client for [port] (the Whisper isolate's inbox).
  RemoteWhisperBackend(this.port, {this.timeout = const Duration(seconds: 60)});

  /// The Whisper isolate's inbox.
  final SendPort port;

  /// Longest wait for one transcription.
  final Duration timeout;

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
        answer = await reply.first.timeout(timeout);
      } on TimeoutException catch (e) {
        throw VoiceException(
          VoiceErrorKind.failed,
          'Whisper hat nicht rechtzeitig geantwortet.',
          cause: e,
        );
      }
      return switch (answer) {
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
