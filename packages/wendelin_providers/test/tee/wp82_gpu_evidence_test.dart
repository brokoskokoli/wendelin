import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'provider_harness.dart';

const _none = GpuAttestationResult(
  GpuVerdict.failed,
  'Keine GPU-Evidenz im Bericht des Anbieters',
  GpuReason.noEvidence,
);

FakeGpuAttestationVerifier _fake() =>
    FakeGpuAttestationVerifier(_none)..localResult = _none;

ProviderProfile _profile(Map<String, Object?> options) => ProviderProfile(
  id: 'p',
  name: 'P',
  type: ProviderType.openaiCompatible,
  defaultModel: 'm',
  privacy: PrivacyLevel.tee,
  authMethod: const NoAuth(),
  options: options,
);

void main() {
  group('Modell ohne GPU-Nachweis (WP82)', () {
    test(
      'vorher: nichts gesendet, Kategorie no_evidence, einmal erlaubt',
      () async {
        final gpu = _fake();
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.before);
        final error =
            ((await h.chat()).last as ErrorEvent).error
                as AttestationFailedException;
        expect(error.stage, 'gpu');
        expect(error.category, GpuReason.noEvidence);
        expect(h.chatRequests, 0);
        // Nothing to retry: the second request is judged without asking again.
        await h.chat();
        expect(gpu.calls, hasLength(1));
        h.provider.allowNextRequestWithoutGpuCheck();
        expect((await h.chat()).last, isA<Done>());
        expect(h.chatRequests, 1);
        expect((await h.chat()).last, isA<ErrorEvent>());
      },
    );

    test(
      'nachher: Anfrage geht raus, kein roter Bericht, nur Hinweis',
      () async {
        final gpu = _fake();
        final h = TeeHarness(gpu: gpu, gpuMode: GpuCheckMode.after);
        final reports = <AttestationReport>[];
        h.provider.reports.listen(reports.add);
        expect((await h.chat()).last, isA<Done>());
        await h.provider.pendingReport();
        expect((await h.chat()).last, isA<Done>());
        expect(h.chatRequests, 2);
        expect(
          reports.where((r) => r.status == AttestationStatus.red),
          isEmpty,
        );
        expect(gpu.calls, isEmpty, reason: 'NVIDIA kann nichts prüfen');
        final gpuEntries = h.log.entries.where(
          (e) => e.kind == AttestationLogKind.gpu,
        );
        expect(gpuEntries, isNotEmpty);
        expect(gpuEntries.last.status, AttestationStatus.yellow);
        expect(
          gpuEntries.last.stages.single.stage,
          AttestationStage.gpuEvidence,
        );
      },
    );

    test('aus: keine GPU-Abfrage, Anfrage geht raus', () async {
      final gpu = _fake();
      final h = TeeHarness(gpu: gpu);
      expect((await h.chat()).last, isA<Done>());
      expect(gpu.localCalls, isEmpty);
    });

    test('hasGpuEvidence: ja, nein, unbekannt', () async {
      final gpu = FakeGpuAttestationVerifier();
      final h = TeeHarness(gpu: gpu);
      expect(await h.provider.hasGpuEvidence('m'), isTrue);
      gpu.localResult = _none;
      expect(await h.provider.hasGpuEvidence('m'), isFalse);
      gpu.localResult = const GpuAttestationResult(
        GpuVerdict.unreachable,
        'x',
        GpuReason.unreachable,
      );
      expect(await h.provider.hasGpuEvidence('m'), isNull);
    });
  });

  group('GPU-Modus je Profil', () {
    test('gpuModeOf liest options.gpuCheck, sonst null', () {
      expect(gpuModeOf(_profile({})), isNull);
      expect(
        gpuModeOf(_profile({gpuCheckOption: 'before'})),
        GpuCheckMode.before,
      );
      expect(gpuModeOf(_profile({gpuCheckOption: 'quatsch'})), isNull);
    });
  });
}
