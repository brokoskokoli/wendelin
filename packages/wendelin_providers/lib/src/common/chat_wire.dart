import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import 'http_transport.dart';

/// The request body as it goes over the wire ([wire]) and the bytes the
/// gateway's receipt is computed over ([plain]; for E2EE the decrypted,
/// compact body).
final class SealedBody {
  /// Creates a sealed body.
  const SealedBody({required this.wire, required this.plain});

  /// Text of the HTTP request body.
  final String wire;

  /// Bytes for the `request.received` hash of the receipt.
  final Uint8List plain;
}

/// Transforms the chat exchange on the wire (end-to-end encryption of the
/// TEE gateway, WP62). One [ChatWire] per HTTP attempt; a retry begins a new
/// one, so nonce, timestamp and keys are never reused.
abstract interface class ChatWireCodec {
  /// Starts the wire exchange for a request to [model]. Throws a
  /// `ProviderException` (before anything is sent) if the request must not
  /// be sent, e.g. because no valid key exists.
  Future<ChatWire> begin({required String model});
}

/// The wire transformation of one HTTP attempt.
abstract interface class ChatWire {
  /// Extra request headers.
  Map<String, String> get headers;

  /// Turns the OpenAI request [body] into the wire body.
  SealedBody seal(Map<String, Object?> body);

  /// Checks the head of a successful (2xx) response; throws a
  /// `ProviderException` if it does not meet the protocol.
  void checkHead(Map<String, String> headers);

  /// Turns one SSE event of the response into a plain one; throws a
  /// `ProviderException` if it cannot be opened. Never lets content pass
  /// that was not decrypted.
  SseEvent open(SseEvent event);
}

/// A [StreamDecoder] that opens each event with [wire] before [inner] sees it.
final class WireStreamDecoder implements StreamDecoder {
  /// Creates the decoder.
  WireStreamDecoder(this.inner, this.wire);

  /// The adapter's decoder.
  final StreamDecoder inner;

  /// The wire of this attempt.
  final ChatWire wire;

  @override
  List<ChatEvent> onEvent(SseEvent event) => inner.onEvent(wire.open(event));

  @override
  List<ChatEvent> onEnd() => inner.onEnd();
}
