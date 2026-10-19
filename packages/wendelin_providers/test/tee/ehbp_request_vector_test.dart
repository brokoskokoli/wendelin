import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/src/tee/tinfoil/ehbp_reference.dart';

/// Cross vector of the request side: recipient key and ephemeral key of the
/// CFRG vector (mode 0, X25519, AES-256-GCM), but with `info = "ehbp request"`.
/// The same constants are checked against the Rust module in
/// `native/attest/src/ehbp_tests.rs` (`request_matches_dart_reference_vector`),
/// so the two independent implementations agree byte for byte.
void main() {
  Uint8List h(String s) => AttestCodec.unhex(s);

  test('the Dart reference reproduces the frozen request vector', () {
    final pk = h(
      '430f4b9859665145a6b1ba274024487bd66f03a2dd577d7753c68d7d7d00c00c',
    );
    final ctx = EhbpReferenceCrypto.setupSender(
      pk,
      h('179d4b53b6365c45b600c4163b61d95cbc2f4d9e36f1695558dce265ab8bab11'),
      'ehbp request'.codeUnits,
    );
    expect(
      AttestCodec.hex(ctx.enc),
      '6c93e09869df3402d7bf231bf540fadd35cd56be14f97178f0954db94b7fc256',
    );
    expect(
      AttestCodec.hex(ctx.export('ehbp response'.codeUnits, 32)),
      'd8f1ee6100814d15c48553fd0d9907039e55c1f0282922c02c81ed973d63d2d3',
    );
    expect(
      AttestCodec.hex(
        ctx.seal(Uint8List.fromList('Hallo Tinfoil'.codeUnits), const []),
      ),
      '90c985f1adc6bd60f3dc00e769da0cc379db1a8b83cfb60376ac13481f',
    );
  });
}
