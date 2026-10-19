import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../attestation_crypto.dart';
import '../codec.dart';
import 'ehbp_crypto.dart';
import 'fake_ehbp_service.dart';

String _hex(Uint8List b) => AttestCodec.hex(b);

/// Contract of [EhbpCrypto]: every implementation (Rust, reference) must
/// pass it. The server side is [FakeEhbpService], whose HPKE receiver and
/// response keys are proven against the CFRG vector and the protocol
/// vectors (`ehbp_reference_test.dart`).
void ehbpCryptoContract(EhbpCrypto Function() create, {required String name}) {
  group('EhbpCrypto $name', () {
    late EhbpCrypto crypto;
    late FakeEhbpService service;
    setUp(() {
      crypto = create();
      service = FakeEhbpService();
    });

    Uint8List u(String s) => Uint8List.fromList(utf8.encode(s));

    Matcher rejects() => throwsA(isA<E2eeCryptoException>());

    test('binds the attested key and returns the TLS pin', () {
      final b = crypto.bindKeyConfig(service.keyConfig, service.reportData);
      expect(b.tlsSpkiSha256, service.tlsSpkiSha256);
    });

    test('refuses a key that is not in report_data[32..64]', () {
      final other = FakeEhbpService(secret: Uint8List(32)..[0] = 7);
      expect(
        () => crypto.bindKeyConfig(other.keyConfig, service.reportData),
        rejects(),
      );
      final rd = Uint8List.fromList(service.reportData)..[63] ^= 1;
      expect(() => crypto.bindKeyConfig(service.keyConfig, rd), rejects());
      expect(
        () => crypto.bindKeyConfig(
          service.keyConfig,
          service.reportData.sublist(0, 63),
        ),
        rejects(),
      );
      expect(
        () => crypto.beginRequest(
          other.keyConfig,
          service.reportData,
          u('geheim'),
        ),
        rejects(),
      );
    });

    test('accepts exactly one suite: id, KEM, KDF, AEAD', () {
      for (final i in [0, 1, 2, 35, 36, 37, 38, 39, 40]) {
        final cfg = Uint8List.fromList(service.keyConfig);
        cfg[i] ^= 1;
        expect(
          () => crypto.bindKeyConfig(cfg, service.reportData),
          rejects(),
          reason: 'byte $i',
        );
      }
      expect(
        () => crypto.bindKeyConfig(
          service.keyConfig.sublist(0, 40),
          service.reportData,
        ),
        rejects(),
      );
    });

    test('the request is HPKE-sealed; the receiver reads it back', () {
      final sealed = crypto.beginRequest(
        service.keyConfig,
        service.reportData,
        u('{"messages":[{"content":"Hallo Wendelin"}]}'),
      );
      expect(sealed.encapsulatedKey, hasLength(32));
      final ex = service.open({
        'Ehbp-Encapsulated-Key': _hex(sealed.encapsulatedKey),
      }, sealed.body);
      expect(utf8.decode(ex.plainBody), contains('Hallo Wendelin'));
      expect(
        utf8.decode(sealed.body, allowMalformed: true),
        isNot(contains('Hallo')),
      );
    });

    test('frames of 64 KiB plaintext, fresh ephemeral key every time', () {
      final plain = Uint8List.fromList(List.generate(70000, (i) => i % 251));
      final a = crypto.beginRequest(
        service.keyConfig,
        service.reportData,
        plain,
      );
      final lens = <int>[];
      for (var p = 0; p < a.body.length;) {
        final l = ByteData.sublistView(a.body).getUint32(p);
        lens.add(l);
        p += 4 + l;
      }
      expect(lens, [65536 + 16, 70000 - 65536 + 16]);
      final ex = service.open({
        'ehbp-encapsulated-key': _hex(a.encapsulatedKey),
      }, a.body);
      expect(ex.plainBody, plain);
      final b = crypto.beginRequest(
        service.keyConfig,
        service.reportData,
        plain,
      );
      expect(b.encapsulatedKey, isNot(a.encapsulatedKey));
    });

    test('an empty body is not encrypted', () {
      expect(
        () => crypto.beginRequest(
          service.keyConfig,
          service.reportData,
          Uint8List(0),
        ),
        rejects(),
      );
    });
  });
  _responseContract(create);
}

void _responseContract(EhbpCrypto Function() create) {
  group('EhbpCrypto response', () {
    late EhbpCrypto crypto;
    late FakeEhbpService service;
    setUp(() {
      crypto = create();
      service = FakeEhbpService();
    });
    Uint8List u(String s) => Uint8List.fromList(utf8.encode(s));
    Matcher rejects() => throwsA(isA<E2eeCryptoException>());

    test('decodes an answer in fragments, even across frame borders', () {
      final sealed = crypto.beginRequest(
        service.keyConfig,
        service.reportData,
        u('x'),
      );
      final ex = service.open({
        'Ehbp-Encapsulated-Key': _hex(sealed.encapsulatedKey),
      }, sealed.body);
      final r = ex.seal([u('data: eins\n\n'), u(''), u('data: [DONE]\n\n')]);
      final d = sealed.session.responseDecoder(AttestCodec.unhex(r.nonceHex));
      final out = BytesBuilder();
      for (var i = 0; i < r.body.length; i += 3) {
        out.add(
          d.push(
            r.body.sublist(i, i + 3 > r.body.length ? r.body.length : i + 3),
          ),
        );
      }
      d.finish();
      expect(utf8.decode(out.toBytes()), 'data: eins\n\ndata: [DONE]\n\n');
    });

    test('fails closed: tag, order, truncation, wrong nonce', () {
      EhbpSealed fresh() =>
          crypto.beginRequest(service.keyConfig, service.reportData, u('x'));
      ({EhbpSealed sealed, Uint8List body, Uint8List nonce}) make(
        List<Uint8List> frames,
      ) {
        final sealed = fresh();
        final ex = service.open({
          'Ehbp-Encapsulated-Key': _hex(sealed.encapsulatedKey),
        }, sealed.body);
        final n = Uint8List(32)..[5] = 9;
        return (sealed: sealed, body: ex.seal(frames, nonce: n).body, nonce: n);
      }

      final t = make([u('eins'), u('zwei')]);
      final bad = Uint8List.fromList(t.body)..[t.body.length - 1] ^= 1;
      var d = t.sealed.session.responseDecoder(t.nonce);
      expect(() => d.push(bad), rejects());
      expect(() => d.push(Uint8List(0)), rejects());
      expect(d.finish, rejects());

      d = t.sealed.session.responseDecoder(t.nonce);
      d.push(t.body.sublist(0, t.body.length - 1));
      expect(d.finish, rejects());

      final other = Uint8List(32)..[5] = 8;
      d = t.sealed.session.responseDecoder(other);
      expect(() => d.push(t.body), rejects());

      d = t.sealed.session.responseDecoder(t.nonce);
      expect(
        () => d.push(Uint8List.fromList([0xff, 0xff, 0xff, 0xff])),
        rejects(),
      );

      expect(() => t.sealed.session.responseDecoder(Uint8List(31)), rejects());
    });
  });
}
