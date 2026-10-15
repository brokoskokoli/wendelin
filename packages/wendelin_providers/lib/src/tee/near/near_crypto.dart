import 'dart:typed_data';

/// Client identity of a NEAR E2EE request: the Ed25519 public key goes into
/// `X-Client-Pub-Key`, the X25519 secret (derived like libsodium's
/// `crypto_sign_ed25519_sk_to_curve25519`) opens the answer.
final class NearIdentity {
  /// Creates an identity.
  const NearIdentity({required this.secret, required this.public});

  /// X25519 secret key (32 bytes).
  final Uint8List secret;

  /// Ed25519 public key (32 bytes).
  final Uint8List public;
}

/// Field encryption of the NEAR AI Cloud E2EE protocol (ADR 0019): X25519 +
/// HKDF-SHA256 (`ed25519_encryption`) + XChaCha20-Poly1305 without AAD. Rust
/// in the app (`native/attest/src/near_e2ee.rs`), `NearReferenceCrypto` in
/// tests. Failures throw `E2eeCryptoException` without key material.
abstract interface class NearCrypto {
  /// A fresh client identity.
  NearIdentity nearGenerateIdentity();

  /// Encrypts [plaintext] to the Ed25519 key [recipientEd25519]; returns the
  /// hex wire format `eph(32) ‖ nonce(24) ‖ ciphertext ‖ tag(16)`.
  String nearEncrypt(Uint8List recipientEd25519, Uint8List plaintext);

  /// Decrypts [wireHex] with the X25519 [secret] of the identity.
  Uint8List nearDecrypt(Uint8List secret, String wireHex);
}
