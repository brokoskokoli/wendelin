import 'dart:typed_data';

import 'package:wendelin_providers/wendelin_providers.dart' as p;

import 'attest_backend.dart';
import 'generated/ehbp.dart' as g;

/// `EhbpCrypto` über das Rust-Modul `native/attest` (WP76c): HPKE-Sender
/// und zustandsbehafteter Antwort-Decoder (Tinfoil EHBP). Fehler werden zu
/// `E2eeCryptoException` mit dem Fehlercode des Moduls, nie mit Schlüsseln
/// oder Klartext.
final class RustEhbpCrypto implements p.EhbpCrypto {
  /// Erstellt die Implementierung.
  const RustEhbpCrypto(this.backend);

  /// Rust-Funktionen.
  final AttestBackend backend;

  @override
  p.EhbpBinding bindKeyConfig(Uint8List keyConfig, Uint8List reportData) =>
      _guard(
        'Schlüsselbindung fehlgeschlagen',
        () => p.EhbpBinding(
          tlsSpkiSha256: backend
              .ehbpBindKeyConfig(keyConfig, reportData)
              .tlsSpkiSha256,
        ),
      );

  @override
  p.EhbpSealed beginRequest(
    Uint8List keyConfig,
    Uint8List reportData,
    Uint8List plaintext,
  ) => _guard('Verschlüsselung fehlgeschlagen', () {
    final (sealed, session) = backend.ehbpBeginRequest(
      keyConfig,
      reportData,
      plaintext,
    );
    return p.EhbpSealed(
      encapsulatedKey: sealed.encapsulatedKey,
      body: sealed.body,
      session: _Session(backend, session),
    );
  });

  /// Nur der Code vor dem Doppelpunkt (`AEAD_DECRYPT_FAILED` …) wird
  /// übernommen; der Rest des Rust-Fehlers gehört nicht in Meldungen.
  static T _guard<T>(String fallback, T Function() call) {
    try {
      return call();
    } on Object catch (e) {
      final m = RegExp(r'\b([A-Z][A-Z_]{4,}):').firstMatch(e.toString());
      throw p.E2eeCryptoException(m == null ? fallback : m.group(1)!);
    }
  }
}

final class _Session implements p.EhbpSession {
  _Session(this._backend, this._session);
  final AttestBackend _backend;
  final g.EhbpSession _session;

  @override
  p.EhbpDecoder responseDecoder(Uint8List responseNonce) =>
      RustEhbpCrypto._guard(
        'Antwortschlüssel nicht ableitbar',
        () => _Decoder(
          _backend,
          _backend.ehbpResponseDecoder(_session, responseNonce),
        ),
      );
}

final class _Decoder implements p.EhbpDecoder {
  _Decoder(this._backend, this._decoder);
  final AttestBackend _backend;
  final g.EhbpResponseDecoder _decoder;

  @override
  Uint8List push(Uint8List data) => RustEhbpCrypto._guard(
    'Entschlüsselung fehlgeschlagen',
    () => _backend.ehbpDecoderPush(_decoder, data),
  );

  @override
  void finish() => RustEhbpCrypto._guard(
    'Entschlüsselung fehlgeschlagen',
    () => _backend.ehbpDecoderFinish(_decoder),
  );
}
