import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/attest/rust_ehbp_crypto.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../../support/fake_attest_backend.dart';

void main() {
  final bytes = Uint8List(41);
  late FakeAttestBackend backend;
  late RustEhbpCrypto crypto;
  setUp(() {
    backend = FakeAttestBackend();
    crypto = RustEhbpCrypto(backend);
  });

  test('Fehler des Moduls werden zu E2eeCryptoException ohne Details', () {
    backend.panic = Exception('KEY_NOT_BOUND: geheimer Schlüssel 1234abcd');
    Object? caught;
    try {
      crypto.bindKeyConfig(bytes, Uint8List(64));
    } on E2eeCryptoException catch (e) {
      caught = e;
    }
    expect((caught! as E2eeCryptoException).reason, 'KEY_NOT_BOUND');
    expect(caught.toString(), isNot(contains('1234abcd')));
  });

  test('ohne erkennbaren Code gilt der feste Text', () {
    backend.panic = StateError('boom mit Klartext');
    expect(
      () => crypto.beginRequest(bytes, Uint8List(64), Uint8List(1)),
      throwsA(
        isA<E2eeCryptoException>().having(
          (e) => e.reason,
          'reason',
          'Verschlüsselung fehlgeschlagen',
        ),
      ),
    );
  });
}
