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

void main() {
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
  });
}
