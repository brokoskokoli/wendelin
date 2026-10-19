import 'dart:typed_data';

/// The TLS pin an attested EHBP key is bound to.
final class EhbpBinding {
  /// Creates the binding.
  const EhbpBinding({required this.tlsSpkiSha256});

  /// SHA-256 of the TLS `SubjectPublicKeyInfo` (`report_data[0..32]`).
  final Uint8List tlsSpkiSha256;
}

/// An encrypted request and the session that opens its answer.
final class EhbpSealed {
  /// Creates the sealed request.
  const EhbpSealed({
    required this.encapsulatedKey,
    required this.body,
    required this.session,
  });

  /// Value of `Ehbp-Encapsulated-Key` (32 bytes, the header is hex).
  final Uint8List encapsulatedKey;

  /// The framed body (`LEN(4, BE) ‖ chunk` per frame).
  final Uint8List body;

  /// Opens the answer.
  final EhbpSession session;
}

/// The secret of one request, used to derive the answer keys.
abstract interface class EhbpSession {
  /// A decoder for the answer; [responseNonce] is the 32 bytes of the
  /// header `Ehbp-Response-Nonce`.
  EhbpDecoder responseDecoder(Uint8List responseNonce);
}

/// Stateful decoder of an EHBP answer body (frames, authentication,
/// sequence). The first error is final: afterwards every call throws and no
/// plaintext is delivered.
abstract interface class EhbpDecoder {
  /// Feeds network bytes; returns the plaintext of all frames that are now
  /// complete and authentic. Throws `E2eeCryptoException` on any violation
  /// (tag, framing, oversize, sequence overflow); the plaintext of the
  /// failing call is dropped.
  Uint8List push(Uint8List data);

  /// End of the body. Throws `E2eeCryptoException` if it ended inside a
  /// frame or length prefix.
  void finish();
}

/// Cryptography of the Encrypted HTTP Body Protocol (Tinfoil), sender side:
/// HPKE `X25519-HKDF-SHA256 / HKDF-SHA256 / AES-256-GCM`, info
/// `ehbp request`. Rust in the app (`native/attest/src/ehbp.rs`),
/// `EhbpReferenceCrypto` in tests. Failures throw `E2eeCryptoException`
/// without key material or plaintext.
abstract interface class EhbpCrypto {
  /// Checks the key configuration (`/.well-known/hpke-keys`, exactly one
  /// suite) and that its key equals `report_data[32..64]`; returns the TLS
  /// pin from `report_data[0..32]`. Throws if the key is not the attested
  /// one.
  EhbpBinding bindKeyConfig(Uint8List keyConfig, Uint8List reportData);

  /// Binds like [bindKeyConfig], then encrypts [plaintext] (not empty) to
  /// the attested key.
  EhbpSealed beginRequest(
    Uint8List keyConfig,
    Uint8List reportData,
    Uint8List plaintext,
  );
}
