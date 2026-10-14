import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import 'attestation_types.dart';
import 'codec.dart';

/// Shared state of the TLS pin (ADR 0014, WP61): the SPKI hash the
/// attestation binds to the gateway domain ([expected]) and the certificate
/// seen on a connection.
///
/// The enforcing HTTP client calls [enforce] on every new connection
/// **before** a byte of the request is sent; a missing pin, an unreadable
/// certificate or a mismatch throws and the request never leaves the
/// device (fail-closed, no provider switch: K28).
final class TlsPinGate {
  /// Creates the gate; [spkiSha256] hashes the DER `SubjectPublicKeyInfo`
  /// of a certificate (Rust in the app).
  TlsPinGate({required Uint8List Function(Uint8List certificateDer) spkiSha256})
    : _spki = spkiSha256;

  final Uint8List Function(Uint8List) _spki;

  String? _expected;
  String? _observed;
  int _generation = 0;

  /// Hex SPKI hash from the latest successful attestation; `null` = none
  /// (every enforced connection is refused).
  String? get expected => _expected;

  /// Hex SPKI hash of the latest connection measured by [observe]; `null`
  /// if there was none or the certificate was unreadable.
  String? get observed => _observed;

  /// Changes whenever [expected] changes; clients drop kept-alive
  /// connections that were checked against an older pin.
  int get generation => _generation;

  /// Sets the pin of the attestation (`null` clears it).
  void expect(String? spkiHex) {
    final value = spkiHex?.toLowerCase();
    if (value == _expected) return;
    _expected = value;
    _generation++;
  }

  /// Forgets the last measurement (before the connection to measure).
  void resetObserved() => _observed = null;

  /// Measures [certificateDer] without judging it.
  void observe(Uint8List? certificateDer) {
    _observed = _hash(certificateDer);
  }

  /// Judges the certificate of a connection; throws
  /// [AttestationFailedException] (stage `tls.spki`) unless it matches
  /// [expected].
  void enforce(Uint8List? certificateDer) {
    final seen = _hash(certificateDer);
    final String? reason;
    if (_expected == null) {
      reason = 'kein Schlüssel aus der Attestierung';
    } else if (seen == null) {
      reason = 'Zertifikat der Verbindung nicht messbar';
    } else if (seen != _expected) {
      reason = 'Zertifikat der Verbindung weicht von der Attestierung ab';
    } else {
      reason = null;
    }
    if (reason == null) return;
    throw AttestationFailedException(
      'TLS-Verbindung nicht verifiziert: $reason',
      stage: AttestationStage.tlsSpki.id,
    );
  }

  String? _hash(Uint8List? der) {
    if (der == null || der.isEmpty) return null;
    try {
      return AttestCodec.hex(_spki(der));
    } on Object {
      return null;
    }
  }
}
