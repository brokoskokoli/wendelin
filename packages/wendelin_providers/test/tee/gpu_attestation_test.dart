import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'provider_harness.dart';
import 'tee_support.dart';

final _nonce = Uint8List.fromList(List.filled(32, 0xcd));

/// Fixture report: `nvidia_payload` has the probe nonce `cdcd…`.
String get _report => jsonEncode(teeJson('model_report_trimmed'));
String get _nras =>
    File('test/fixtures/tee/nras_response.json').readAsStringSync();

NrasGpuVerifier _verifier(
  FutureOr<http.Response> Function(http.Request) handler, {
  Duration timeout = const Duration(seconds: 1),
}) => NrasGpuVerifier(
  tokenChecker: FakeNrasTokenChecker(),
  baseUrl: Uri.parse('https://gateway.test/v1'),
  client: MockClient((r) async => handler(r)),
  nonceSource: () => _nonce,
  timeout: timeout,
);

http.Response _ok(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: {'content-type': 'application/json'},
);

/// Real NRAS answer (2026-10-18) for the real nonce; evidence stand-in.
class _Signed {
  static final nonce =
      '75b040ace9638a02cde08c76511c28c7f4ed40af4d97b6afed837805df831eab';
  static String get response =>
      File('test/fixtures/tee/nras_signed.json').readAsStringSync();
  static String get jwks =>
      File('test/fixtures/tee/nras_jwks_subset.json').readAsStringSync();
  static final now = DateTime.fromMillisecondsSinceEpoch(
    1792318698 * 1000 + 60000,
    isUtc: true,
  );

  static NrasGpuVerifier verifier({
    String? nras,
    String? keys,
    int jwksStatus = 200,
    DateTime? at,
  }) {
    final clock = at ?? now;
    final client = MockClient(
      (r) async => r.url.path.endsWith('jwks.json')
          ? http.Response(keys ?? jwks, jwksStatus)
          : _ok(nras ?? response),
    );
    return NrasGpuVerifier(
      baseUrl: Uri.parse('https://gateway.test/v1'),
      evidenceSource: () async => (
        payload: <String, Object?>{
          'nonce': nonce,
          'evidence_list': [<String, Object?>{}],
        },
        nonce: nonce,
      ),
      client: client,
      tokenChecker: NrasTokenVerifier(
        jwks: NrasJwks(client: client, clock: () => clock),
        clock: () => clock,
      ),
    );
  }
}

void main() {
  group('NrasGpuVerifier mit echtem signiertem NRAS-Token (WP83)', () {
    String tamper(String body, void Function(List<Object?>) f) {
      final d = jsonDecode(body) as List<Object?>;
      f(d);
      return jsonEncode(d);
    }

    test('Signatur geprüft → verified mit signatureChecked', () async {
      final r = await _Signed.verifier().verify(model: 'm');
      expect(r.verdict, GpuVerdict.verified);
      expect(r.signatureChecked, isTrue);
    });

    test(
      'Signatur verändert → failed nras_signature (kein verified)',
      () async {
        final body = tamper(_Signed.response, (d) {
          final t = ((d[0]! as List)[1]! as String).split('.');
          t[2] =
              t[2].substring(0, 20) +
              (t[2][20] == 'A' ? 'B' : 'A') +
              t[2].substring(21);
          (d[0]! as List)[1] = t.join('.');
        });
        final r = await _Signed.verifier(nras: body).verify(model: 'm');
        expect(r.verdict, GpuVerdict.failed);
        expect(r.category, GpuReason.signature);
        expect(r.signatureChecked, isFalse);
      },
    );

    test(
      'Claims verändert → failed (Claims kommen nur aus geprüftem Token)',
      () async {
        final body = tamper(_Signed.response, (d) {
          final t = ((d[0]! as List)[1]! as String).split('.');
          final claims = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(t[1]))),
          ) as Map<String, Object?>;
          claims['x-nvidia-overall-att-result'] = true;
          claims['eat_nonce'] = 'cd' * 32;
          t[1] = base64Url
              .encode(utf8.encode(jsonEncode(claims)))
              .replaceAll('=', '');
          (d[0]! as List)[1] = t.join('.');
        });
        final r = await _Signed.verifier(nras: body).verify(model: 'm');
        expect(r.verdict, GpuVerdict.failed);
        expect(r.category, GpuReason.signature);
      },
    );

    test('abgelaufenes Token → failed nras_signature', () async {
      final r = await _Signed.verifier(
        at: _Signed.now.add(const Duration(hours: 3)),
      ).verify(model: 'm');
      expect(r.verdict, GpuVerdict.failed);
      expect(r.category, GpuReason.signature);
      expect(r.detail, contains('jwt_expired'));
    });

    test('unbekannte kid → failed', () async {
      final r = await _Signed.verifier(
        keys: _Signed.jwks.replaceAll('01a45dc1', 'deadbeef'),
      ).verify(model: 'm');
      expect(r.verdict, GpuVerdict.failed);
      expect(r.detail, contains('jwt_unknown_kid'));
    });

    test(
      'JWKS nicht abrufbar → unreachable (wie „NRAS nicht erreichbar“)',
      () async {
        final r = await _Signed.verifier(jwksStatus: 503).verify(model: 'm');
        expect(r.verdict, GpuVerdict.unreachable);
        expect(r.category, GpuReason.jwks);
        expect(r.ok, isFalse);
      },
    );

    test(
      'abgetrenntes GPU-Token passt nicht zum signierten Digest → failed',
      () async {
        final body = tamper(_Signed.response, (d) {
          final gpus = d[1]! as Map<String, Object?>;
          gpus['GPU-0'] = '${gpus['GPU-0']}x';
        });
        final r = await _Signed.verifier(nras: body).verify(model: 'm');
        expect(r.verdict, GpuVerdict.failed);
        expect(r.category, GpuReason.signature);
      },
    );

    test(
      'zusätzliches abgetrenntes GPU-Token ohne signierten Digest → failed',
      () async {
        final body = tamper(_Signed.response, (d) {
          final gpus = d[1]! as Map<String, Object?>;
          gpus['GPU-9'] = gpus['GPU-0'];
        });
        final r = await _Signed.verifier(nras: body).verify(model: 'm');
        expect(r.verdict, GpuVerdict.failed);
        expect(r.category, GpuReason.signature);
      },
    );

    test('Nonce der Evidenz ≠ Nonce im geprüften Token → failed', () async {
      final client = MockClient(
        (r) async => r.url.path.endsWith('jwks.json')
            ? http.Response(_Signed.jwks, 200)
            : _ok(_Signed.response),
      );
      final v = NrasGpuVerifier(
        baseUrl: Uri.parse('https://gateway.test/v1'),
        evidenceSource: () async => (
          payload: <String, Object?>{
            'nonce': 'ab' * 32,
            'evidence_list': [<String, Object?>{}],
          },
          nonce: 'ab' * 32,
        ),
        client: client,
        tokenChecker: NrasTokenVerifier(
          jwks: NrasJwks(client: client, clock: () => _Signed.now),
          clock: () => _Signed.now,
        ),
      );
      final r = await v.verify(model: 'm');
      expect(r.category, GpuReason.nonceMismatch);
    });
  });

  group('NrasGpuVerifier mit den Probe-Antworten', () {
    test(
      'Bericht und NRAS-Antwort bestätigt, Nonce passt → verified',
      () async {
        final seen = <Uri>[];
        final v = _verifier((r) {
          seen.add(r.url);
          return r.url.host == 'nras.attestation.nvidia.com'
              ? _ok(_nras)
              : _ok(_report);
        });
        final result = await v.verify(model: 'z-ai/glm-5.3-flash');
        expect(result.verdict, GpuVerdict.verified);
        expect(seen.first.queryParameters['model'], 'z-ai/glm-5.3-flash');
        expect(seen.first.queryParameters['nonce'], 'cd' * 32);
        expect(seen.last.host, 'nras.attestation.nvidia.com');
      },
    );

    test(
      'andere Nonce als in der Evidenz → failed, NRAS wird nicht gefragt',
      () async {
        var nrasCalls = 0;
        final v = NrasGpuVerifier(
          tokenChecker: FakeNrasTokenChecker(),
          baseUrl: Uri.parse('https://gateway.test/v1'),
          client: MockClient((r) async {
            if (r.url.host == 'nras.attestation.nvidia.com') nrasCalls++;
            return _ok(_report);
          }),
          nonceSource: () => Uint8List.fromList(List.filled(32, 0x01)),
        );
        expect((await v.verify(model: 'm')).verdict, GpuVerdict.failed);
        expect(nrasCalls, 0);
      },
    );

    test(
      'evidenceSource: kein Aufruf am Gateway, Nonce der Quelle zählt',
      () async {
        final seen = <Uri>[];
        NrasGpuVerifier make(String nonce, {String? payloadNonce}) =>
            NrasGpuVerifier(
              tokenChecker: FakeNrasTokenChecker(),
              baseUrl: Uri.parse('https://gateway.test/v1'),
              client: MockClient((r) async {
                seen.add(r.url);
                return _ok(_nras);
              }),
              evidenceSource: () async => (
                payload: <String, Object?>{
                  'nonce': payloadNonce ?? nonce,
                  'evidence_list': [<String, Object?>{}],
                },
                nonce: nonce,
              ),
            );
        final ok = await make('cd' * 32).verify(model: 'm');
        expect(ok.verdict, GpuVerdict.verified);
        expect(seen.map((u) => u.host), ['nras.attestation.nvidia.com']);
        // Evidenz bindet die Nonce der Quelle nicht → NRAS wird nicht gefragt
        seen.clear();
        final bad = await make(
          'cd' * 32,
          payloadNonce: '01' * 32,
        ).verify(model: 'm');
        expect(bad.verdict, GpuVerdict.failed);
        expect(seen, isEmpty);
        // keine Evidenz
        final none = NrasGpuVerifier(
          tokenChecker: FakeNrasTokenChecker(),
          baseUrl: Uri.parse('https://gateway.test/v1'),
          client: MockClient((r) async => _ok(_nras)),
          evidenceSource: () async => null,
        );
        expect((await none.verifyLocal(model: 'm')).verdict, GpuVerdict.failed);
      },
    );

    test('NRAS-Gesamtergebnis false → failed', () async {
      // Rebuild the overall JWT payload with a negative result.
      final decoded = jsonDecode(_nras) as List;
      final overall = ((decoded.first as List)[1]) as String;
      final parts = overall.split('.');
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, Object?>;
      claims['x-nvidia-overall-att-result'] = false;
      final forged =
          '${parts[0]}.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.${parts[2]}';
      ((decoded.first as List))[1] = forged;
      final v = _verifier(
        (r) => r.url.host == 'nras.attestation.nvidia.com'
            ? _ok(jsonEncode(decoded))
            : _ok(_report),
      );
      expect((await v.verify(model: 'm')).verdict, GpuVerdict.failed);
    });

    test(
      'NRAS 503 und Netzfehler → unreachable, Zeitüberschreitung → timeout',
      () async {
        var v = _verifier(
          (r) => r.url.host == 'nras.attestation.nvidia.com'
              ? http.Response('x', 503)
              : _ok(_report),
        );
        expect((await v.verify(model: 'm')).verdict, GpuVerdict.unreachable);
        v = _verifier((r) => throw http.ClientException('offline'));
        expect((await v.verify(model: 'm')).verdict, GpuVerdict.unreachable);
        v = _verifier(
          (r) => Completer<http.Response>().future,
          timeout: const Duration(milliseconds: 20),
        );
        expect((await v.verify(model: 'm')).verdict, GpuVerdict.timeout);
      },
    );
  });

  group('NrasGpuVerifier.verifyLocal (ohne NVIDIA)', () {
    test('Nonce passt: verified, NRAS wird nie gefragt', () async {
      final hosts = <String>[];
      final v = _verifier((r) {
        hosts.add(r.url.host);
        return _ok(_report);
      });
      expect((await v.verifyLocal(model: 'm')).verdict, GpuVerdict.verified);
      expect(hosts, ['gateway.test']);
    });

    test('fremde Nonce in der Evidenz: failed', () async {
      final report = jsonDecode(_report) as Map<String, Object?>;
      final raw = report['nvidia_payload'];
      final payload = raw is String
          ? jsonDecode(raw) as Map<String, Object?>
          : raw! as Map<String, Object?>;
      payload['nonce'] = 'ab' * 32;
      report['nvidia_payload'] = payload;
      final v = _verifier((r) => _ok(jsonEncode(report)));
      final r = await v.verifyLocal(model: 'm');
      expect(r.verdict, GpuVerdict.failed);
      expect(r.detail, contains('Nonce'));
    });

    test('Bericht nicht abrufbar: unreachable', () async {
      final v = _verifier((r) => http.Response('x', 503));
      expect((await v.verifyLocal(model: 'm')).verdict, GpuVerdict.unreachable);
    });
  });

  group('AttestedProvider: GPU-Modus', () {
    const bad = GpuAttestationResult(GpuVerdict.failed, 'abgelehnt');

    test('off: NRAS wird nie gefragt', () async {
      final gpu = FakeGpuAttestationVerifier();
      final h = TeeHarness(gpu: gpu);
      await h.chat();
      expect(gpu.calls, isEmpty);
    });

    group('vorher (blockierend, fail-closed)', () {
      test('grün: Anfrage geht raus, Ergebnis gilt für die Sitzung', () async {
        final gpu = FakeGpuAttestationVerifier();
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.before);
        await h.chat();
        await h.chat();
        expect(gpu.calls, ['m']);
        expect(h.chatRequests, 2);
      });

      test('Prüfung wird neu fällig nach neuer Attestierung', () async {
        final gpu = FakeGpuAttestationVerifier();
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.before);
        await h.chat();
        await h.provider.reattest();
        await h.chat();
        expect(gpu.calls, ['m', 'm']);
      });

      for (final (name, result, unavailable) in [
        ('rot', bad, false),
        (
          'NRAS nicht erreichbar',
          const GpuAttestationResult(GpuVerdict.unreachable),
          true,
        ),
        (
          'Zeitüberschreitung',
          const GpuAttestationResult(GpuVerdict.timeout),
          true,
        ),
      ]) {
        test('$name: nichts gesendet, Fehler mit Stufe gpu', () async {
          final gpu = FakeGpuAttestationVerifier(result);
          final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.before);
          final events = await h.chat();
          final error =
              (events.last as ErrorEvent).error as AttestationFailedException;
          expect(error.stage, 'gpu');
          expect(error.unavailable, unavailable);
          expect(h.chatRequests, 0);
          // Not cached: the next request checks again and may pass.
          gpu.result = const GpuAttestationResult(GpuVerdict.verified);
          expect((await h.chat()).last, isA<Done>());
          expect(gpu.calls, hasLength(2));
        });
      }

      test('„ohne GPU-Prüfung senden“ gilt nur für eine Anfrage', () async {
        final gpu = FakeGpuAttestationVerifier(bad);
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.before);
        h.provider.allowNextRequestWithoutGpuCheck();
        expect((await h.chat()).last, isA<Done>());
        expect(gpu.calls, isEmpty);
        expect((await h.chat()).last, isA<ErrorEvent>());
        expect(h.chatRequests, 1);
      });

      test('Inhalt wird erst nach der grünen Prüfung gesendet', () async {
        final gpu = FakeGpuAttestationVerifier()..gate = Completer<void>();
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.before);
        final done = h.chat();
        await pumpEventQueue();
        expect(gpu.calls, ['m']);
        expect(h.chatRequests, 0);
        gpu.gate!.complete();
        await done;
        expect(h.chatRequests, 1);
      });
    });

    group('nachher (asynchron)', () {
      test(
        'Anfrage läuft sofort, Prüfung danach; grün meldet grünen Bericht',
        () async {
          final gpu = FakeGpuAttestationVerifier()..gate = Completer<void>();
          final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.after);
          final events = await h.chat();
          expect(events.last, isA<Done>());
          expect(h.chatRequests, 1);
          await h.provider.pendingReport();
          await pumpEventQueue();
          expect(gpu.calls, ['m']);
          gpu.gate!.complete();
          await pumpEventQueue();
          expect(h.log.entries.last.kind, AttestationLogKind.gpu);
          expect(h.log.entries.last.status, AttestationStatus.green);
          await h.chat();
          expect(gpu.calls, ['m'], reason: 'gecacht');
        },
      );

      test('Fehlschlag: roter Bericht, nächste Anfrage prüft vorher und wird blockiert', () async {
        final gpu = FakeGpuAttestationVerifier(bad);
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.after);
        final reports = <AttestationReport>[];
        h.provider.reports.listen(reports.add);
        await h.chat();
        await h.provider.pendingReport();
        await pumpEventQueue();
        final red = reports.lastWhere((r) => r.status == AttestationStatus.red);
        expect(red.detail, contains('GPU'));
        expect(red.reasonCode, 'gpu_failed');
        expect(h.log.entries.last.kind, AttestationLogKind.gpu);
        // The next request asks first and is blocked while NRAS says no.
        final before = h.chatRequests;
        final events = await h.chat();
        expect(
          (events.last as ErrorEvent).error,
          isA<AttestationFailedException>(),
        );
        expect(h.chatRequests, before);
        // Green again: the request passes.
        gpu.result = const GpuAttestationResult(GpuVerdict.verified);
        expect((await h.chat()).last, isA<Done>());
      });
    });

    group('lokale Nonce-Bindung und Protokoll', () {
      test('off: gar kein GPU-Abruf, weder Evidenz noch NRAS (WP77)', () async {
        final gpu = FakeGpuAttestationVerifier();
        final h = TeeHarness(gpu: gpu);
        await h.chat();
        await h.chat();
        expect(gpu.localCalls, isEmpty);
        expect(gpu.calls, isEmpty);
      });

      test('nachher: lokale Bindung läuft einmal je Modell vorher', () async {
        final gpu = FakeGpuAttestationVerifier();
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.after);
        await h.chat();
        await h.chat();
        expect(gpu.localCalls, ['m']);
      });

      test('nachher: Bindung schlägt fehl → rot, nichts gesendet', () async {
        final gpu = FakeGpuAttestationVerifier()
          ..localResult = const GpuAttestationResult(
            GpuVerdict.failed,
            'GPU-Evidenz bindet die Nonce nicht',
            GpuReason.nonceMismatch,
          );
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.after);
        final reports = <AttestationReport>[];
        h.provider.reports.listen(reports.add);
        final events = await h.chat();
        final error =
            (events.last as ErrorEvent).error as AttestationFailedException;
        expect(error.stage, 'gpu');
        expect(error.unavailable, isFalse);
        expect(h.chatRequests, 0);
        await pumpEventQueue();
        final red = reports.lastWhere((r) => r.status == AttestationStatus.red);
        expect(red.status, AttestationStatus.red);
        expect(red.reasonCode, 'gpu_failed');
      });

      test(
        'off: Session-Protokoll nennt „nicht über NVIDIA geprüft“',
        () async {
          final h = TeeHarness(gpu: FakeGpuAttestationVerifier());
          await h.chat();
          final session = h.log.entries.firstWhere(
            (e) => e.kind == AttestationLogKind.session,
          );
          final gpuStage = session.stages.singleWhere(
            (s) => s.stage == AttestationStage.gpu,
          );
          expect(gpuStage.outcome, StageOutcome.info);
          expect(gpuStage.detail, 'GPU: nicht über NVIDIA geprüft');
        },
      );

      test('before: Session-Protokoll hat keine Info-Stufe', () async {
        final h = TeeHarness(
          gpu: FakeGpuAttestationVerifier(),
          gpuMode: GpuCheckMode.before,
        );
        await h.chat();
        final session = h.log.entries.firstWhere(
          (e) => e.kind == AttestationLogKind.session,
        );
        expect(
          session.stages.where((s) => s.stage == AttestationStage.gpu),
          isEmpty,
        );
      });

      test('NRAS grün: Text „geprüft (NRAS, Signatur geprüft)“', () async {
        final h = TeeHarness(
          gpu: FakeGpuAttestationVerifier(),
          gpuMode: GpuCheckMode.before,
        );
        await h.chat();
        final entry = h.log.entries.firstWhere(
          (e) => e.kind == AttestationLogKind.gpu,
        );
        expect(entry.status, AttestationStatus.green);
        expect(entry.stages.single.detail, 'geprüft (NRAS, Signatur geprüft)');
      });

      test(
        'Log nennt die Quelle: via=nras (vorher), via=local (nachher)',
        () async {
          final before = TeeHarness(
            gpu: FakeGpuAttestationVerifier(),
            gpuMode: GpuCheckMode.before,
          );
          await before.chat();
          expect(
            before.diagnostics,
            contains('Wendelin/attest: gpu gpu=pass via=nras'),
          );
          final after = TeeHarness(
            gpu: FakeGpuAttestationVerifier(),
            gpuMode: GpuCheckMode.after,
          );
          await after.chat();
          expect(
            after.diagnostics,
            contains('Wendelin/attest: gpu gpu=pass via=local'),
          );
          expect(
            after.log.entries
                .where((e) => e.kind == AttestationLogKind.gpu)
                .map((e) => e.stages.single.detail),
            contains('Nonce-Bindung lokal geprüft, nicht über NVIDIA geprüft'),
          );
        },
      );

      test('ohne verifizierte Signatur steht „Signatur ungeprüft“', () async {
        final h = TeeHarness(
          gpu: FakeGpuAttestationVerifier(
            const GpuAttestationResult(GpuVerdict.verified),
          ),
          gpuMode: GpuCheckMode.before,
        );
        await h.chat();
        expect(
          h.log.entries
              .firstWhere(
                (e) =>
                    e.kind == AttestationLogKind.gpu &&
                    e.stages.single.detail!.startsWith('geprüft'),
              )
              .stages
              .single
              .detail,
          'geprüft (NRAS, Signatur ungeprüft)',
        );
      });

      test('nachher: lokale Bindung vor der ersten Anfrage', () async {
        final gpu = FakeGpuAttestationVerifier()
          ..localResult = const GpuAttestationResult(GpuVerdict.failed, 'x');
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.after);
        expect((await h.chat()).last, isA<ErrorEvent>());
        expect(h.chatRequests, 0);
      });
    });

    test('nachher: Fehlschlag sperrt nur das betroffene Modell', () async {
      final gpu = FakeGpuAttestationVerifier(bad);
      final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.after);
      await h.chat();
      await h.provider.pendingReport();
      await pumpEventQueue();
      final other = await h.provider
          .chat(
            ChatRequest(
              messages: [Message.user('Hi')],
              model: 'n',
              maxTokens: 5,
            ),
          )
          .toList();
      expect(other.last, isA<Done>(), reason: 'Modell n war nie auffällig');
      expect((await h.chat()).last, isA<ErrorEvent>(), reason: 'Modell m ja');
    });
  });
}
