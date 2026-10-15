import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'near_support.dart';
import 'tee_support.dart';

TeeServer serverFor(Map<String, Object?> doc, {int status = 200}) =>
    TeeServer({'attestation/report': jsonBody(doc, status: status)});

StageResult stage(AttestationResult r, AttestationStage s) =>
    r.stages.firstWhere((x) => x.stage == s);

Iterable<StageResult> stagesOf(AttestationResult r, AttestationStage s) =>
    r.stages.where((x) => x.stage == s);

void main() {
  group('NearVerifier gegen die aufgezeichnete Attestierung', () {
    late FakeAttestationCrypto crypto;
    setUp(() => crypto = FakeAttestationCrypto());

    test('grün: Stufen, Sitzung, Schlüssel und Anfrageform', () async {
      final server = serverFor(nearReport());
      final result = await nearVerifier(server, crypto).attest();
      expect(
        result.status,
        AttestationStatus.green,
        reason: '${result.stages}',
      );
      for (final s in [
        AttestationStage.tcb,
        AttestationStage.nonceBinding,
        AttestationStage.eventLog,
        AttestationStage.composeHash,
        AttestationStage.gateway,
        AttestationStage.e2eeKey,
      ]) {
        expect(stage(result, s).outcome, StageOutcome.pass, reason: s.id);
      }
      final session = result.session!;
      expect(session.workloadId, nearModel);
      expect(
        AttestCodec.hex(session.e2eeKey!.publicKey),
        '5a0210f2442c79355784f9de021985429561da5bacc3a4424b01ac52b7e0caff',
      );
      expect(session.composeHash, hasLength(64));
      final q = server.requests.single.url.queryParameters;
      expect(q['provider'], 'near');
      expect(q['signing_algo'], 'ed25519');
      expect(q['include_tls_fingerprint'], 'true');
      expect(q['nonce'], AttestCodec.hex(nearNonce));
      expect(server.requests.single.headers['authorization'], 'Bearer test');
      expect(server.requests.single.headers['x-no-aliasing'], 'true');
      expect(
        stage(result, AttestationStage.provenance).outcome,
        StageOutcome.info,
      );
    });

    test('Compose-Allowlist: bekannter Hash grün, fremder rot', () async {
      final doc = nearReport();
      final model =
          (doc['model_attestations']! as List<Object?>).first!
              as Map<String, Object?>;
      final hash =
          ((model['info']! as Map)['tcb_info']! as Map)['compose_hash']!
              as String;
      final ok = await nearVerifier(
        serverFor(doc),
        crypto,
        trusted: {hash},
      ).attest();
      expect(ok.status, AttestationStatus.green);
      final bad = await nearVerifier(
        serverFor(doc),
        crypto,
        trusted: {'ab' * 32},
      ).attest();
      expect(bad.status, AttestationStatus.red);
      expect(
        stage(bad, AttestationStage.provenance).outcome,
        StageOutcome.fail,
      );
    });

    test('falsche Nonce im Bericht oder im Quote ist rot', () async {
      final wrong = Uint8List.fromList(nearNonce)..[0] ^= 1;
      final a = await NearVerifier(
        crypto: crypto,
        baseUrl: Uri.parse('https://cloud-api.test/v1'),
        model: nearModel,
        profileId: 'near',
        headers: () async => {},
        client: serverFor(nearReport()).client,
        nonceSource: () => wrong,
      ).attest();
      expect(a.status, AttestationStatus.red);

      final doc = nearReport();
      editModel(
        doc,
        (m) =>
            m['intel_quote'] = flipHex(m['intel_quote']! as String, 1136 + 70),
      );
      final b = await nearVerifier(serverFor(doc), crypto).attest();
      expect(b.status, AttestationStatus.red);
      expect(
        stage(b, AttestationStage.nonceBinding).outcome,
        StageOutcome.fail,
      );
    });

    test('anderer Signaturschlüssel als im Quote gebunden ist rot', () async {
      final doc = nearReport();
      editModel(doc, (m) {
        m['signing_public_key'] = flipHex(
          m['signing_public_key']! as String,
          3,
        );
      });
      final r = await nearVerifier(serverFor(doc), crypto).attest();
      expect(r.status, AttestationStatus.red);
      expect(
        stage(r, AttestationStage.nonceBinding).outcome,
        StageOutcome.fail,
      );
      expect(r.session, isNull);
    });

    test('anderes TLS-Zertifikat im Bericht bindet nicht', () async {
      final doc = nearReport();
      editGateway(
        doc,
        (g) => g['tls_cert_fingerprint'] = flipHex(
          g['tls_cert_fingerprint']! as String,
          0,
        ),
      );
      final r = await nearVerifier(serverFor(doc), crypto).attest();
      expect(r.status, AttestationStatus.red);
      expect(stage(r, AttestationStage.gateway).outcome, StageOutcome.fail);
    });

    test('manipuliertes Ereignisprotokoll und Compose sind rot', () async {
      final doc = nearReport();
      editModel(doc, (m) {
        final log = m['event_log']! as List<Object?>;
        final e = log.firstWhere((e) => (e! as Map)['imr'] == 3)! as Map;
        e['event_payload'] = 'aa${e['event_payload']}';
        m['event_log'] = log;
      });
      final a = await nearVerifier(serverFor(doc), crypto).attest();
      expect(a.status, AttestationStatus.red);
      expect(stage(a, AttestationStage.eventLog).outcome, StageOutcome.fail);

      final doc2 = nearReport();
      editModel(doc2, (m) {
        final tcb = (m['info']! as Map)['tcb_info']! as Map;
        tcb['app_compose'] = '${tcb['app_compose']} ';
      });
      final b = await nearVerifier(serverFor(doc2), crypto).attest();
      expect(stage(b, AttestationStage.composeHash).outcome, StageOutcome.fail);
    });

    test('Debug-TD ist rot', () async {
      final doc = nearReport();
      editModel(doc, (m) {
        final q = m['intel_quote']! as String;
        final at = (48 + 120) * 2;
        m['intel_quote'] = q.replaceRange(at, at + 2, '01');
      });
      final r = await nearVerifier(serverFor(doc), crypto).attest();
      expect(r.status, AttestationStatus.red);
      expect(
        stagesOf(
          r,
          AttestationStage.quote,
        ).any((s) => s.outcome == StageOutcome.fail),
        isTrue,
      );
    });

    test(
      'Modell-TCB OutOfDate ist rot, Gateway-TCB OutOfDate nur Hinweis',
      () async {
        final red = await nearVerifier(
          serverFor(nearReport()),
          FakeAttestationCrypto(tcbStatus: TcbStatus.outOfDate),
        ).attest();
        expect(red.status, AttestationStatus.red);
        expect(stage(red, AttestationStage.tcb).outcome, StageOutcome.fail);

        final doc = nearReport();
        final gwQuote = AttestCodec.unhex(
          (doc['gateway_attestation']! as Map)['intel_quote']! as String,
        );
        final r = await nearVerifier(
          serverFor(doc),
          SplitTcbCrypto(crypto, gwQuote, TcbStatus.outOfDate),
        ).attest();
        expect(r.status, AttestationStatus.green);
        final g = stage(r, AttestationStage.gateway);
        expect(g.outcome, StageOutcome.warn);
        expect(g.detail, contains('nur verschlüsselte Inhalte'));
        expect(r.notes, isNotEmpty);
      },
    );

    test(
      'Bericht für ein anderes Modell oder ohne Kandidaten ist rot',
      () async {
        final r = await nearVerifier(
          serverFor(nearReport()),
          crypto,
          model: 'Qwen/Qwen3.8-27B',
        ).attest();
        expect(r.status, AttestationStatus.red);
        final doc = nearReport()..['model_attestations'] = <Object?>[];
        expect(
          (await nearVerifier(serverFor(doc), crypto).attest()).status,
          AttestationStatus.red,
        );
        final partial = <String, Object?>{'foo': 1};
        expect(
          (await nearVerifier(serverFor(partial), crypto).attest()).status,
          AttestationStatus.red,
        );
      },
    );

    test(
      'Netz- und HTTP-Fehler sind gelb, Unsinn rot, Kollateral gelb',
      () async {
        expect(
          (await nearVerifier(
            serverFor({}, status: 402),
            crypto,
          ).attest()).status,
          AttestationStatus.yellow,
        );
        final garbage = TeeServer({
          'attestation/report': (_) => http.Response('keine json', 200),
        });
        expect(
          (await nearVerifier(garbage, crypto).attest()).status,
          AttestationStatus.red,
        );
        final offline = FakeAttestationCrypto(
          collateralError: const CollateralUnavailableException('offline'),
        );
        expect(
          (await nearVerifier(
            serverFor(nearReport()),
            offline,
          ).attest()).status,
          AttestationStatus.yellow,
        );
      },
    );

    test('mehrere Kandidaten: der erste gültige zählt', () async {
      final doc = nearReport();
      final list = doc['model_attestations']! as List<Object?>;
      final good = copyJson(list.first! as Map<String, Object?>);
      final bad = copyJson(good)
        ..['signing_public_key'] = flipHex(
          good['signing_public_key']! as String,
          5,
        );
      doc['model_attestations'] = [bad, good];
      final r = await nearVerifier(serverFor(doc), crypto).attest();
      expect(r.status, AttestationStatus.green, reason: '${r.stages}');
      expect(
        r.stages.any((s) => s.detail?.contains('2 Modellinstanzen') ?? false),
        isTrue,
      );
    });

    test('GPU-Evidenz stammt vom gewählten Kandidaten, mit der Nonce des '
        'Quotes', () async {
      final doc = nearReport();
      final list = doc['model_attestations']! as List<Object?>;
      final good = copyJson(list.first! as Map<String, Object?>)
        ..['nvidia_payload'] = jsonEncode({
          'arch': 'GUT',
          'nonce': AttestCodec.hex(nearNonce),
        });
      final bad = copyJson(good)
        ..['signing_public_key'] = flipHex(
          good['signing_public_key']! as String,
          5,
        )
        ..['nvidia_payload'] = jsonEncode({'arch': 'SCHLECHT'});
      doc['model_attestations'] = [bad, good];
      final v = nearVerifier(serverFor(doc), crypto);
      expect(await v.gpuEvidence(), isNull, reason: 'vor der Prüfung');
      final r = await v.attest();
      expect(r.status, AttestationStatus.green, reason: '${r.stages}');
      final e = (await v.gpuEvidence())!;
      expect(e.payload['arch'], 'GUT');
      expect(e.nonce, AttestCodec.hex(nearNonce));
      // rot: keine Evidenz übrig
      doc['model_attestations'] = [bad];
      final v2 = nearVerifier(serverFor(doc), crypto);
      await v2.attest();
      expect(await v2.gpuEvidence(), isNull);
    });

    test('TLS-Pin: Fingerabdruck des Gateways wird zur Erwartung', () async {
      final gate = TlsPinGate(spkiSha256: (_) => Uint8List(32));
      final doc = nearReport();
      final fp =
          (doc['gateway_attestation']! as Map)['tls_cert_fingerprint']!
              as String;
      // Verbindung zeigt ein anderes Zertifikat: rot, keine Erwartung gesetzt.
      gate.observe(Uint8List.fromList([1]));
      final bad = await nearVerifier(
        serverFor(doc),
        crypto,
        gate: gate,
      ).attest();
      expect(bad.status, AttestationStatus.red);
      expect(stage(bad, AttestationStage.tlsSpki).outcome, StageOutcome.fail);
      expect(gate.expected, isNull);
      // Verbindung zeigt das attestierte Zertifikat.
      final match = TlsPinGate(spkiSha256: (_) => AttestCodec.unhex(fp))
        ..observe(Uint8List.fromList([1]));
      final ok = await nearVerifier(
        serverFor(doc),
        crypto,
        gate: match,
      ).attest();
      expect(ok.status, AttestationStatus.green);
      expect(match.expected, fp);
    });

    test('Pin-Speicher meldet ein Update der Flotte', () async {
      final pins = MemoryPinStore();
      final first = await nearVerifier(
        serverFor(nearReport()),
        crypto,
        pins: pins,
      ).attest();
      expect(first.pinChange, PinChange.first);
      expect(
        (await nearVerifier(
          serverFor(nearReport()),
          crypto,
          pins: pins,
        ).attest()).pinChange,
        PinChange.none,
      );
      final doc = nearReport();
      editModel(doc, (m) {
        final tcb = (m['info']! as Map)['tcb_info']! as Map;
        tcb['app_compose'] = '${tcb['app_compose']}';
      });
      // Nur eine andere Modellinstanz mit anderem Schlüssel gilt als Wechsel.
      final other = nearReportFor('11' * 32);
      final changed = await nearVerifier(
        serverFor(other),
        crypto,
        pins: pins,
      ).attest();
      expect(changed.pinChange, PinChange.changed, reason: '${changed.stages}');
    });
  });

  group(
    'NearVerifier: Quittung (aufgezeichnet, Streaming mit x-no-aliasing)',
    () {
      final ex = nearExchange();
      final stream = ex['stream']! as Map<String, Object?>;
      final sig = stream['signature']! as Map<String, Object?>;
      late AttestedSession session;
      final crypto = FakeAttestationCrypto();

      setUp(() async {
        final r = await nearVerifier(serverFor(nearReport()), crypto).attest();
        session = r.session!;
      });

      Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

      Future<ReceiptResult> verify({
        Map<String, Object?>? doc,
        String? request,
        String? response,
        int status = 200,
      }) {
        final server = TeeServer({
          'signature/': jsonBody(doc ?? sig, status: status),
        });
        return nearVerifier(server, crypto).verifyReceipt(
          ReceiptRef(id: stream['chat_id']! as String, session: session),
          b(request ?? stream['request_body']! as String),
          b(response ?? stream['response_body']! as String),
        );
      }

      test('Quittung des Modells passt zu den übertragenen Bytes', () async {
        final r = await verify();
        expect(r.status, AttestationStatus.green, reason: '${r.stages}');
        expect(r.stages.map((s) => s.stage), [
          AttestationStage.receiptFetch,
          AttestationStage.receiptSignature,
          AttestationStage.receiptBinding,
          AttestationStage.requestHash,
          AttestationStage.responseHash,
        ]);
        expect(r.stages.every((s) => s.outcome == StageOutcome.pass), isTrue);
      });

      test('Chat-Id kommt aus dem Antwortstrom und der Antwort', () {
        final verifier = nearVerifier(serverFor(nearReport()), crypto);
        ExchangeRecord rec(String body) => ExchangeRecord(
          requestBytes: Uint8List(0),
          status: 200,
          responseHeaders: const {},
          responseBytes: b(body),
          completed: true,
        );
        expect(
          verifier.receiptIdOf(rec(stream['response_body']! as String)),
          stream['chat_id'],
        );
        final plain = ex['plain']! as Map<String, Object?>;
        expect(
          verifier.receiptIdOf(rec(plain['response_body']! as String)),
          plain['chat_id'],
        );
        expect(verifier.receiptIdOf(rec('')), isNull);
      });

      test('veränderte Anfrage- oder Antwortbytes sind rot', () async {
        final req = (stream['request_body']! as String).replaceFirst(
          '"stream":true',
          '"stream":false',
        );
        final a = await verify(request: req);
        expect(a.status, AttestationStatus.red);
        expect(
          a.stages
              .firstWhere((s) => s.stage == AttestationStage.requestHash)
              .outcome,
          StageOutcome.fail,
        );
        final resp = '${stream['response_body']}data: {}\n\n';
        final c = await verify(response: resp);
        expect(
          c.stages
              .firstWhere((s) => s.stage == AttestationStage.responseHash)
              .outcome,
          StageOutcome.fail,
        );
      });

      test(
        'falsche Signatur, fremder Schlüssel und anderes Modell sind rot',
        () async {
          final badSig = {
            ...sig,
            'signature': flipHex(sig['signature']! as String, 2),
          };
          final a = await verify(doc: badSig);
          expect(
            a.stages
                .firstWhere((s) => s.stage == AttestationStage.receiptSignature)
                .outcome,
            StageOutcome.fail,
          );
          final foreign = {...sig, 'signing_address': '11' * 32};
          final b2 = await verify(doc: foreign);
          expect(b2.status, AttestationStatus.red);
          expect(
            b2.stages
                .firstWhere((s) => s.stage == AttestationStage.receiptBinding)
                .outcome,
            StageOutcome.fail,
          );
          final text = (sig['text']! as String).replaceFirst(
            nearModel,
            'anderes/modell',
          );
          final c = await verify(doc: {...sig, 'text': text});
          expect(c.status, AttestationStatus.red);
        },
      );

      test(
        'Gateway-Signatur ist nur mit Hinweis grün, nur vom Gateway-Schlüssel',
        () async {
          final gw = AttestCodec.hex(session.receiptKeys['gateway']!);
          final r = await verify(
            doc: {...sig, 'signature_kind': 'gateway', 'signing_address': gw},
          );
          // Signatur gilt dem Text des Modells, nicht dem des Gateways: rot.
          expect(r.status, AttestationStatus.red);
        },
      );

      test('nicht abrufbar ist gelb (Wiederholung), unlesbar rot', () async {
        expect((await verify(status: 500)).status, AttestationStatus.yellow);
        expect((await verify(doc: {'x': 1})).status, AttestationStatus.red);
      });
    },
  );
}

/// In-memory [AttestationPinStore].
final class MemoryPinStore implements AttestationPinStore {
  final Map<String, AttestationPin> _pins = {};

  @override
  Future<AttestationPin?> load(String profileId) async => _pins[profileId];

  @override
  Future<void> save(String profileId, AttestationPin pin) async =>
      _pins[profileId] = pin;
}
