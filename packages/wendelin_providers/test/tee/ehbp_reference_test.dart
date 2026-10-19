import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_providers/src/tee/attestation_crypto.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/testing.dart';

Uint8List h(String s) => AttestCodec.unhex(s);

void main() {
  ehbpCryptoContract(EhbpReferenceCrypto.new, name: 'Referenz (Dart)');

  // CFRG test vector (rust-hpke test-vectors-5f503c5.json): mode 0, KEM
  // 0x0020, KDF 1, AEAD 2 (AES-256-GCM): the HPKE part of the reference is
  // proven by an independent implementation.
  test('HPKE key schedule matches the CFRG vector (X25519/AES-256-GCM)', () {
    final skR = h(
      '497b4502664cfea5d5af0b39934dac72242a74f8480451e1aee7d6a53320333d',
    );
    final pkR = EhbpReferenceCrypto.publicKey(skR);
    expect(
      AttestCodec.hex(pkR),
      '430f4b9859665145a6b1ba274024487bd66f03a2dd577d7753c68d7d7d00c00c',
    );
    final info = h('4f6465206f6e2061204772656369616e2055726e');
    final ctx = EhbpReferenceCrypto.setupSender(
      pkR,
      h('179d4b53b6365c45b600c4163b61d95cbc2f4d9e36f1695558dce265ab8bab11'),
      info,
    );
    expect(
      AttestCodec.hex(ctx.enc),
      '6c93e09869df3402d7bf231bf540fadd35cd56be14f97178f0954db94b7fc256',
    );
    expect(
      AttestCodec.hex(ctx.sharedSecret),
      '3101c54c3a4f87439eaac080699ed9bbcc726ffe44e860c0424ccb7e3e2ead7b',
    );
    expect(
      AttestCodec.hex(ctx.key),
      'f50b0609186798729ed0564b36ef2ef8044f1f9d05636874d1f46c819c7a669f',
    );
    expect(AttestCodec.hex(ctx.baseNonce), '151d9929e2449747889bc923');
    final pt = h('4265617574792069732074727574682c20747275746820626561757479');
    expect(
      AttestCodec.hex(ctx.seal(pt, h('436f756e742d30'))),
      'e5d84cd531cfb583096e7cfa9641bd3079cf3a91cda813c52deb5f512be9931980a41de125a925cdad859d5b7a',
    );
    expect(
      AttestCodec.hex(ctx.seal(pt, h('436f756e742d31'))),
      '2c43aff25343fdbff864506f0818b9d87df84ea01b1a2144d23b4d40c26bf655fdf197fe40297a8aebeed5cc2d',
    );
    expect(
      AttestCodec.hex(ctx.export(const [], 32)),
      'ded6cffafaea6b812cbf3e241e88332adbc077aca81512914213810ee291770a',
    );
    expect(
      AttestCodec.hex(ctx.export(h('54657374436f6e74657874'), 32)),
      '7c5ded445732c14fe09727d29b4251c0fd38455fe8440571e687f0886aac94d2',
    );
    // The receiver side derives the same context.
    final rx = EhbpReferenceCrypto.setupReceiver(skR, ctx.enc, info);
    expect(rx.key, ctx.key);
    expect(
      rx.open(
        h(
          'e5d84cd531cfb583096e7cfa9641bd3079cf3a91cda813c52deb5f512be9931980a41de125a925cdad859d5b7a',
        ),
        h('436f756e742d30'),
      ),
      pt,
    );
  });

  // The vectors of the protocol reference, frozen with the Rust crate.
  test('the 25 response vectors of the reference (v0.4.1)', () {
    final all = jsonDecode(
      File('../../native/attest/tests/ehbp/crypto.json').readAsStringSync(),
    ) as List<Object?>;
    var n = 0;
    for (final raw in all) {
      final v = raw! as Map<String, Object?>;
      final op = v['operation']! as String;
      if (op == 'token_roundtrip') continue;
      final i = v['inputs']! as Map<String, Object?>;
      final exp = v['expect']! as Map<String, Object?>;
      final id = v['id'];
      Uint8List b(String k) => h(i[k]! as String);
      n++;
      if (op == 'compute_nonce') {
        final d = EhbpReferenceCrypto.decoder(
          Uint8List(32),
          Uint8List(32),
          Uint8List(32),
        );
        final base = b('nonceBase');
        final seq = ByteData.sublistView(b('seqHex')).getUint64(0);
        final got = Uint8List.fromList(base);
        for (var k = 0; k < 8; k++) {
          got[11 - k] ^= (seq >> (8 * k)) & 0xff;
        }
        expect(AttestCodec.hex(got), exp['body_hex'], reason: '$id');
        expect(d.nonceFor(0), hasLength(12));
        continue;
      }
      EhbpReferenceDecoder? d;
      try {
        d = EhbpReferenceCrypto.decoder(
          b('exportedSecret'),
          b('requestEnc'),
          b('responseNonce'),
        );
      } on E2eeCryptoException {
        expect(exp['outcome'], 'error', reason: '$id');
        continue;
      }
      if (op == 'derive_keys') {
        expect(
          AttestCodec.hex([...d.key, ...d.nonceBase]),
          exp['body_hex'],
          reason: '$id',
        );
        continue;
      }
      final out = BytesBuilder();
      Object? error;
      final wire = b('encryptedResponse');
      try {
        for (var k = 0; k < wire.length; k++) {
          out.add(d.push(wire.sublist(k, k + 1)));
        }
        d.finish();
      } on E2eeCryptoException catch (e) {
        error = e;
      }
      if (exp['outcome'] == 'ok') {
        expect(error, isNull, reason: '$id');
        expect(AttestCodec.hex(out.toBytes()), exp['body_hex'], reason: '$id');
      } else {
        expect(error, isNotNull, reason: '$id');
        expect(out.length, exp['bytes_emitted_before_error'], reason: '$id');
      }
    }
    expect(n, 25);
  });
}
