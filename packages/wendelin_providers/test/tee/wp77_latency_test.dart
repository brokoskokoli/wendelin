import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'provider_harness.dart';

/// SPKI hash the probe attestation lists for `api.redpill.ai`.
const _pinA =
    'c68585e7dc00a55d3082a9c860cb916e1788c5daec51505e413d27ab94f7d4c7';

/// Gate whose „certificate“ `A` has the pin of the probe attestation.
TlsPinGate _gate() => TlsPinGate(
  spkiSha256: (der) => Uint8List.fromList([
    for (var i = 0; i < _pinA.length; i += 2)
      int.parse(_pinA.substring(i, i + 2), radix: 16),
  ]),
);

/// Stand-in for the pinned client: judges like it (see the pin tests).
final class _FakeConnectionClient extends http.BaseClient {
  _FakeConnectionClient(this._next, this.gate, this.enforce);

  final http.Client _next;
  final TlsPinGate gate;
  final bool enforce;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final cert = Uint8List.fromList(utf8.encode('A'));
    if (enforce) {
      gate.enforce(cert);
    } else {
      gate.resetObserved();
      gate.observe(cert);
    }
    return _next.send(request);
  }
}

TeeHarness _harness(
  TlsPinGate gate, {
  FakeGpuAttestationVerifier? gpu,
  GpuCheckMode gpuMode = GpuCheckMode.off,
  Uri? baseUrl,
}) => TeeHarness(
  baseUrl: baseUrl ?? Uri.parse('https://api.redpill.ai/v1'),
  tlsPin: gate,
  gpu: gpu,
  gpuMode: gpuMode,
  pinWrap: (base, {required enforce}) =>
      _FakeConnectionClient(base, gate, enforce),
);

String _payload({List<Object?>? evidence, String nonce = 'cd'}) => jsonEncode({
  'nvidia_payload': jsonEncode({
    'nonce': nonce * 32,
    'evidence_list': evidence ?? <Object?>[],
    'arch': 'HOPPER',
  }),
});

NrasGpuVerifier _nras(FutureOr<http.Response> Function(http.Request) handler) =>
    NrasGpuVerifier(
      tokenChecker: FakeNrasTokenChecker(),
      baseUrl: Uri.parse('https://gateway.test/v1'),
      client: MockClient((r) async => handler(r)),
      nonceSource: () => Uint8List.fromList(List.filled(32, 0xcd)),
    );

void main() {
  group('WP77: Vorwärmen, Parallelität, Wiederverwendung', () {
    test(
      'Attestierung und GPU-Evidenz laufen parallel (Modus vorher)',
      () async {
        final gpu = FakeGpuAttestationVerifier()..gate = Completer<void>();
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.before)
          ..attestationGate = Completer<void>();
        final done = h.chat();
        await pumpEventQueue();
        expect(
          h.server.count('aci/attestation'),
          1,
          reason: 'Attestierung läuft',
        );
        expect(gpu.calls, ['m'], reason: 'GPU-Prüfung startet gleichzeitig');
        expect(
          h.chatRequests,
          0,
          reason: 'nichts gesendet, bevor beides fertig',
        );
        h.attestationGate!.complete();
        await pumpEventQueue();
        expect(h.chatRequests, 0, reason: 'GPU-Prüfung steht noch aus');
        gpu.gate!.complete();
        expect((await done).last, isA<Done>());
        expect(h.chatRequests, 1);
      },
    );

    test('Modus Aus: keine GPU-Evidenz, auch nicht beim Vorwärmen', () async {
      final gpu = FakeGpuAttestationVerifier();
      final h = TeeHarness(gpu: gpu);
      await h.provider.warmUp();
      await h.chat();
      expect(gpu.localCalls, isEmpty);
      expect(gpu.calls, isEmpty);
    });

    test(
      'warmUp holt auch die GPU-Prüfung; die Anfrage wiederholt sie nicht',
      () async {
        final gpu = FakeGpuAttestationVerifier();
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.before);
        await h.provider.warmUp();
        expect(gpu.calls, ['m']);
        expect((await h.chat()).last, isA<Done>());
        expect(gpu.calls, ['m']);
        expect(h.server.count('aci/attestation'), 1);
      },
    );

    test(
      'warmUp-GPU-Fehlschlag sperrt nicht, die Anfrage scheitert genauso',
      () async {
        final gpu = FakeGpuAttestationVerifier(
          const GpuAttestationResult(
            GpuVerdict.failed,
            'keine Evidenz',
            GpuReason.noEvidence,
          ),
        );
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.before);
        await h.provider.warmUp();
        expect(h.provider.locked, isFalse);
        final events = await h.chat();
        final error =
            (events.last as ErrorEvent).error as AttestationFailedException;
        expect(error.stage, 'gpu');
        expect(error.message, contains('[no_evidence]'));
        expect(h.chatRequests, 0);
      },
    );

    test('warmUp zählt „ohne GPU-Prüfung senden“ nicht ab', () async {
      final gpu = FakeGpuAttestationVerifier(
        const GpuAttestationResult(GpuVerdict.failed, 'x'),
      );
      final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.before);
      h.provider.allowNextRequestWithoutGpuCheck();
      await h.provider.warmUp();
      expect((await h.chat()).last, isA<Done>(), reason: 'einmal erlaubt');
    });

    test(
      'warmUp öffnet die Verbindung einmal; erneut erst nach der Leerlaufzeit',
      () async {
        final h = TeeHarness();
        await h.provider.warmUp();
        expect(h.server.count('models'), 1);
        await h.provider.warmUp();
        expect(h.server.count('models'), 1, reason: 'Verbindung noch offen');
        h.clock.advance(const Duration(minutes: 5));
        await h.provider.warmUp();
        expect(h.server.count('models'), 2);
        expect(h.server.count('aci/attestation'), 1, reason: 'Sitzung gilt');
      },
    );

    test(
      'Vorwärmen scheitert an Attestierung: kein Verbindungsaufbau',
      () async {
        final h = TeeHarness()..attestationStatus = 503;
        await h.provider.warmUp();
        expect(h.server.count('models'), 0);
      },
    );

    test('parallele Anfragen und Vorwärmen attestieren nur einmal', () async {
      final h = TeeHarness()..attestationGate = Completer<void>();
      final warm = h.provider.warmUp();
      final chat = h.chat();
      await pumpEventQueue();
      h.attestationGate!.complete();
      await warm;
      await chat;
      expect(h.server.count('aci/attestation'), 1);
    });

    test('Grund jeder Sitzungsprüfung steht im Log', () async {
      final h = TeeHarness();
      await h.chat();
      expect(
        h.diagnostics,
        contains('Wendelin/attest: Sitzungsprüfung startet (Grund=no-session)'),
      );
      await h.provider.reattest();
      expect(
        h.diagnostics,
        contains('Wendelin/attest: Sitzungsprüfung startet (Grund=reattest)'),
      );
    });

    group('Sitzung des Vorgängers übernehmen (Profil neu aufgebaut)', () {
      Future<(TeeHarness, TlsPinGate)> attested() async {
        final gate = _gate();
        final h = _harness(gate);
        await h.provider.warmUp();
        expect(h.provider.session, isNotNull);
        return (h, gate);
      }

      test(
        'gleicher Endpunkt: keine neue Attestierung, Pin und GPU übernommen',
        () async {
          final (old, oldGate) = await attested();
          final gate = _gate();
          final gpu = FakeGpuAttestationVerifier();
          final fresh = _harness(gate, gpu: gpu, gpuMode: GpuCheckMode.before);
          expect(fresh.provider.adoptSessionOf(old.provider), isTrue);
          expect(gate.expected, oldGate.expected);
          expect(gate.expected, isNotNull);
          expect(fresh.provider.session, same(old.provider.session));
          expect((await fresh.chat()).last, isA<Done>());
          expect(fresh.server.count('aci/attestation'), 0);
          expect(
            fresh.diagnostics,
            contains(
              'Wendelin/attest: Sitzung übernommen (Profil neu aufgebaut)',
            ),
          );
        },
      );

      test('anderer Endpunkt (Profil geändert): keine Übernahme', () async {
        final (old, _) = await attested();
        final fresh = _harness(
          _gate(),
          baseUrl: Uri.parse('https://other.test/v1'),
        );
        expect(fresh.provider.adoptSessionOf(old.provider), isFalse);
        expect(fresh.provider.session, isNull);
        await fresh.chat();
        expect(fresh.server.count('aci/attestation'), 1);
      });

      test('abgelaufene Sitzung: keine Übernahme', () async {
        final (old, _) = await attested();
        final fresh = _harness(_gate());
        fresh.clock.advance(const Duration(days: 4000));
        expect(fresh.provider.adoptSessionOf(old.provider), isFalse);
      });

      test('gesperrter Vorgänger: keine Übernahme', () async {
        final crypto = FakeAttestationCrypto(
          ed25519Result: true,
          quoteError: const QuoteVerificationException('x'),
        );
        final old = TeeHarness(
          crypto: crypto,
          baseUrl: Uri.parse('https://api.redpill.ai/v1'),
          tlsPin: _gate(),
        );
        await old.provider.warmUp();
        expect(old.provider.locked, isTrue);
        final fresh = _harness(_gate());
        expect(fresh.provider.adoptSessionOf(old.provider), isFalse);
      });

      test(
        'Vorgänger ohne Pin (Prüfung läuft gerade): keine Übernahme',
        () async {
          final (old, oldGate) = await attested();
          oldGate.expect(null); // a new attestation clears the pin first
          final fresh = _harness(_gate());
          expect(fresh.provider.adoptSessionOf(old.provider), isFalse);
        },
      );

      test('Provider mit eigener Sitzung übernimmt nichts', () async {
        final (old, _) = await attested();
        final (other, _) = await attested();
        expect(other.provider.adoptSessionOf(old.provider), isFalse);
      });
    });
  });

  group('WP77: Grund einer fehlgeschlagenen GPU-Prüfung', () {
    test('leere evidence_list (Gateway ohne GPU-Evidenz): no_evidence, NRAS nicht gefragt', () async {
      var nrasCalls = 0;
      final v = _nras((r) {
        if (r.url.host == 'nras.attestation.nvidia.com') nrasCalls++;
        return http.Response(_payload(), 200);
      });
      final r = await v.verify(model: 'z-ai/glm-5.2');
      expect(r.verdict, GpuVerdict.failed);
      expect(r.category, GpuReason.noEvidence);
      expect(r.detail, contains('keine GPU-Evidenz'));
      expect(nrasCalls, 0);
      expect((await v.verifyLocal(model: 'm')).category, GpuReason.noEvidence);
    });

    test('kein nvidia_payload im Bericht: no_evidence', () async {
      final v = _nras((r) => http.Response('{"intel_quote":"x"}', 200));
      expect((await v.verify(model: 'm')).category, GpuReason.noEvidence);
    });

    test(
      'NRAS 400 INVALID_EVIDENCE: HTTP-Status und Fehlername im Grund',
      () async {
        final v = _nras(
          (r) => r.url.host == 'nras.attestation.nvidia.com'
              ? http.Response(
                  '{"status":"BAD_REQUEST","errorCode":4005,'
                  '"message":"INVALID_EVIDENCE"}',
                  400,
                )
              : http.Response(_payload(evidence: [<String, Object?>{}]), 200),
        );
        final r = await v.verify(model: 'm');
        expect(r.verdict, GpuVerdict.failed);
        expect(r.category, 'nras_http_400');
        expect(r.detail, contains('HTTP 400'));
        expect(r.detail, contains('INVALID_EVIDENCE'));
      },
    );

    test(
      'NRAS-Fehlertext, der kein Fehlername ist, kommt nicht ins Protokoll',
      () async {
        final v = _nras(
          (r) => r.url.host == 'nras.attestation.nvidia.com'
              ? http.Response('{"message":"secret text here"}', 400)
              : http.Response(_payload(evidence: [<String, Object?>{}]), 200),
        );
        final r = await v.verify(model: 'm');
        expect(r.detail, isNot(contains('secret')));
        expect(r.detail, contains('HTTP 400'));
      },
    );

    test(
      'NRAS 503, Bericht 404 und Zeitüberschreitung haben je ihre Kategorie',
      () async {
        var v = _nras(
          (r) => r.url.host == 'nras.attestation.nvidia.com'
              ? http.Response('x', 503)
              : http.Response(_payload(evidence: [<String, Object?>{}]), 200),
        );
        expect((await v.verify(model: 'm')).category, 'nras_http_503');
        v = _nras((r) => http.Response('x', 404));
        expect((await v.verify(model: 'm')).category, 'report_http_404');
        v = NrasGpuVerifier(
          tokenChecker: FakeNrasTokenChecker(),
          baseUrl: Uri.parse('https://gateway.test/v1'),
          client: MockClient((r) => Completer<http.Response>().future),
          timeout: const Duration(milliseconds: 20),
        );
        final t = await v.verify(model: 'm');
        expect(t.verdict, GpuVerdict.timeout);
        expect(t.category, GpuReason.timeout);
      },
    );

    test(
      'Fehlschlag steht mit Kategorie in Log, Protokoll und Bericht',
      () async {
        final gpu = FakeGpuAttestationVerifier(
          const GpuAttestationResult(
            GpuVerdict.failed,
            'NRAS lehnt die Evidenz ab (HTTP 400, INVALID_EVIDENCE)',
            'nras_http_400',
          ),
        );
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.before);
        final reports = <AttestationReport>[];
        h.provider.reports.listen(reports.add);
        final events = await h.chat();
        final error =
            (events.last as ErrorEvent).error as AttestationFailedException;
        expect(error.message, contains('HTTP 400'));
        expect(error.message, contains('[nras_http_400]'));
        expect(
          h.diagnostics,
          contains(
            'Wendelin/attest: gpu gpu=fail reason=nras_http_400 via=nras',
          ),
        );
        final entry = h.log.entries.lastWhere(
          (e) => e.kind == AttestationLogKind.gpu,
        );
        expect(entry.stages.single.detail, contains('INVALID_EVIDENCE'));
        expect(entry.stages.single.code, 'gpu_failed');
        await pumpEventQueue();
        final red = reports.lastWhere((r) => r.status == AttestationStatus.red);
        expect(red.detail, contains('INVALID_EVIDENCE'));
        expect(red.reasonCode, 'gpu_failed');
      },
    );

    test('nicht erreichbar: Code gpu_unavailable im Protokoll', () async {
      final gpu = FakeGpuAttestationVerifier(
        const GpuAttestationResult(
          GpuVerdict.timeout,
          'Zeitüberschreitung',
          GpuReason.timeout,
        ),
      );
      final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.before);
      await h.chat();
      final entry = h.log.entries.lastWhere(
        (e) => e.kind == AttestationLogKind.gpu,
      );
      expect(entry.stages.single.code, 'gpu_unavailable');
      expect(
        h.diagnostics,
        contains('Wendelin/attest: gpu gpu=fail reason=timeout via=nras'),
      );
    });
  });

  group('WP77: gehaltene Verbindung', () {
    test('der erzwingende Client hält Verbindungen mehrere Minuten offen', () {
      final gate = _gate();
      final enforcing = PinnedHttpClient(gate: gate, enforce: true);
      final measuring = PinnedHttpClient(gate: gate, enforce: false);
      expect(enforcing.debugHttpClient.idleTimeout, const Duration(minutes: 5));
      expect(
        measuring.debugHttpClient.idleTimeout,
        const Duration(seconds: 15),
        reason: 'der messende Client verwirft Verbindungen ohnehin',
      );
      enforcing.close();
      measuring.close();
    });
  });
}
