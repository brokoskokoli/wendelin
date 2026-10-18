import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/gpu_check_migration.dart';
import 'package:wendelin/di/provider_setup.dart';
import 'package:wendelin/ui/settings/gpu_check_section.dart';
import 'package:wendelin/ui/settings/provider_setup/model_step.dart';
import 'package:wendelin/ui/settings/provider_setup_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/fakes.dart';

import '../support/tee_app_support.dart';
import '../support/test_env.dart';
import '../ui/helpers.dart';

const _none = GpuAttestationResult(
  GpuVerdict.failed,
  'Keine GPU-Evidenz im Bericht des Anbieters',
  GpuReason.noEvidence,
);

Future<TestEnv> _openPhala(
  WidgetTester tester, {
  FakeGpuAttestationVerifier? gpu,
}) async {
  final env = TestEnv(
    storedProfiles: true,
    llmFactory: (profile, _) => scriptedTee(
      verifier: ScriptedVerifier(),
      gateway: ScriptedGateway(),
      gpu: gpu,
    ),
  );
  setView(tester, const Size(390, 2400));
  await tester.pumpWidget(env.app(home: const ProviderSetupScreen()));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Phala (RedPill)'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('apiKey')), 'k-geheim');
  await tester.tap(find.text('Verbindung testen'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Modell prüfen'));
  await tester.pumpAndSettle();
  return env;
}

Future<void> _save(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Speichern'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Speichern'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Einstellung im Profil: Standard aus, „Vorher“ wird im Profil '
      'gespeichert', (tester) async {
    final env = await _openPhala(tester);
    expect(find.text('GPU-Prüfung über NVIDIA'), findsOneWidget);
    expect(find.byKey(const ValueKey('noGpuEvidence')), findsNothing);
    await tester.tap(find.text('Vorher'));
    await tester.pumpAndSettle();
    await _save(tester);
    final p = (await env.storage.providerProfiles.list()).single;
    expect(gpuModeOf(p), GpuCheckMode.before);
    expect(env.notifier.permissionRequests, 0);
  });

  testWidgets('ohne Wahl wird „aus“ gespeichert', (tester) async {
    final env = await _openPhala(tester);
    await _save(tester);
    expect(
      gpuModeOf((await env.storage.providerProfiles.list()).single),
      GpuCheckMode.off,
    );
  });

  testWidgets('„Nachher“ bittet um die Benachrichtigungs-Berechtigung', (
    tester,
  ) async {
    final env = await _openPhala(tester);
    env.notifier.granted = false;
    await tester.tap(find.text('Nachher'));
    await tester.pumpAndSettle();
    await _save(tester);
    expect(env.notifier.permissionRequests, 1);
    expect(
      gpuModeOf((await env.storage.providerProfiles.list()).single),
      GpuCheckMode.after,
    );
  });

  testWidgets('Modell ohne GPU-Nachweis: Einrichtung geht weiter, Hinweis '
      'statt „Modell nicht nutzbar“', (tester) async {
    final gpu = FakeGpuAttestationVerifier(_none)..localResult = _none;
    final env = await _openPhala(tester, gpu: gpu);
    expect(find.text('Modell nicht nutzbar'), findsNothing);
    expect(find.byKey(const ValueKey('setupFailure')), findsNothing);
    expect(find.byKey(const ValueKey('noGpuEvidence')), findsOneWidget);
    expect(find.textContaining(noGpuEvidenceHint), findsWidgets);
    // WP78: the acceptance names the restriction.
    expect(find.byKey(const ValueKey('restrictionSetupNote')), findsOneWidget);
    expect(find.textContaining('GPU-Nachweis des Anbieters'), findsWidgets);
    await _save(tester);
    final p = (await env.storage.providerProfiles.list()).single;
    expect(
      (await env.storage.settings.get(
        AppSettings.teeAccepted(p.id, p.defaultModel),
      ))?['stages'],
      contains('gpu.evidence'),
    );
  });

  testWidgets(
    'Golden Abschlussschritt: GPU-Abschnitt und Hinweiskarte',
    tags: ['golden'],
    (tester) async {
      final gpu = FakeGpuAttestationVerifier(_none)..localResult = _none;
      final env = TestEnv(
        storedProfiles: true,
        llmFactory: (profile, _) => scriptedTee(
          verifier: ScriptedVerifier(),
          gateway: ScriptedGateway(),
          gpu: gpu,
        ),
      );
      setView(tester, const Size(390, 1500));
      await tester.pumpWidget(
        env.app(
          home: RepaintBoundary(
            key: goldenKey,
            child: const ProviderSetupScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phala (RedPill)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('apiKey')), 'k');
      await tester.tap(find.text('Verbindung testen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modell prüfen'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('noGpuEvidence')), findsOneWidget);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/provider_abschluss_gpu.png'),
      );
    },
  );

  testWidgets('Nicht-TEE-Profil zeigt den Abschnitt nicht', (tester) async {
    final env = TestEnv(storedProfiles: true);
    setView(tester, const Size(390, 2400));
    await tester.pumpWidget(env.app(home: const ProviderSetupScreen()));
    await tester.pumpAndSettle();
    expect(find.text('GPU-Prüfung über NVIDIA'), findsNothing);
  });

  testWidgets('Modellauswahl: Modell ohne Nachweis bleibt wählbar, mit '
      'Hinweiszeile', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: modelStep(
              connection: null,
              models: const [
                ModelInfo(id: 'glm-5.2', displayName: 'glm-5.2'),
                ModelInfo(id: 'gpt-x', displayName: 'gpt-x'),
              ],
              model: TextEditingController(),
              noGpuEvidence: const {'glm-5.2'},
              failure: null,
              busy: false,
              onChanged: () {},
              onPick: picked.add,
              onProbe: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text(noGpuEvidenceHint), findsOneWidget);
    await tester.tap(find.text('glm-5.2'));
    expect(picked, ['glm-5.2']);
  });

  group('Migration des globalen Werts', () {
    ProviderProfile tee(String id, {Map<String, Object?> options = const {}}) =>
        ProviderProfile(
          id: id,
          name: id,
          type: ProviderType.openaiCompatible,
          baseUrl: 'https://api.redpill.ai/v1',
          defaultModel: 'm',
          privacy: PrivacyLevel.tee,
          authMethod: const NoAuth(),
          options: {'attestation': 'phala', ...options},
        );

    test(
      'übernimmt den Wert für TEE-Profile ohne eigenen, entfernt ihn',
      () async {
        final storage = openInMemoryStorage();
        await storage.settings.set(AppSettings.legacyGpuCheck, 'before');
        await storage.providerProfiles.save(tee('a'));
        await storage.providerProfiles.save(
          tee('b', options: {gpuCheckOption: 'after'}),
        );
        await storage.providerProfiles.save(
          ProviderProfile(
            id: 'c',
            name: 'c',
            type: ProviderType.anthropic,
            defaultModel: 'm',
            privacy: PrivacyLevel.standard,
            authMethod: const NoAuth(),
          ),
        );
        await migrateGlobalGpuCheck(storage.settings, storage.providerProfiles);
        expect(
          gpuModeOf((await storage.providerProfiles.get('a'))!),
          GpuCheckMode.before,
        );
        expect(
          gpuModeOf((await storage.providerProfiles.get('b'))!),
          GpuCheckMode.after,
          reason: 'eigener Wert bleibt',
        );
        expect(
          (await storage.providerProfiles.get('c'))!.options,
          isNot(contains(gpuCheckOption)),
        );
        expect(await storage.settings.get(AppSettings.legacyGpuCheck), isNull);
        // Second run: nothing left to do.
        await migrateGlobalGpuCheck(storage.settings, storage.providerProfiles);
      },
    );

    test('ohne alten Wert: Profile bleiben unverändert', () async {
      final storage = openInMemoryStorage();
      await storage.providerProfiles.save(tee('a'));
      await migrateGlobalGpuCheck(storage.settings, storage.providerProfiles);
      expect((await storage.providerProfiles.get('a'))!, tee('a'));
    });

    test(
      'Profil angelegt nach der Migration: Standard aus statt Altwert',
      () async {
        final storage = openInMemoryStorage();
        await migrateGlobalGpuCheck(storage.settings, storage.providerProfiles);
        await storage.providerProfiles.save(tee('neu'));
        expect(gpuModeOf((await storage.providerProfiles.get('neu'))!), isNull);
      },
    );
  });

  group('Einrichtung: Probe eines bestehenden Profils', () {
    ProviderProfile editing(GpuCheckMode mode) => ProviderProfile(
      id: 'phala-1',
      name: 'Phala',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://api.redpill.ai/v1',
      defaultModel: 'm',
      privacy: PrivacyLevel.tee,
      authMethod: const ApiKeyAuth('provider.phala-1.apiKey'),
      options: {'attestation': 'phala', gpuCheckOption: mode.name},
    );

    Future<SetupTestResult> probe(
      FakeGpuAttestationVerifier gpu,
      GpuCheckMode mode,
    ) async {
      final secrets = InMemorySecretStore();
      await secrets.write('provider.phala-1.apiKey', 'k-geheim');
      final session = ProviderSetupSession(
        template: providerTemplateById('phala')!,
        profileId: 'phala-1',
        secrets: secrets,
        existing: editing(mode),
        ids: SequentialIdGenerator(prefix: 'k'),
        // The profile's own mode applies to the provider, as in the app.
        create: (profile, _) => scriptedTee(
          verifier: ScriptedVerifier(),
          gateway: ScriptedGateway(),
          gpu: gpu,
          gpuMode: gpuModeOf(profile) ?? GpuCheckMode.off,
        ),
      );
      return session.probe(model: 'm');
    }

    test('„Vorher“ im Profil: Modell ohne Nachweis bleibt wählbar, Hinweis '
        'statt „Modell nicht nutzbar“', () async {
      final gpu = FakeGpuAttestationVerifier(_none)..localResult = _none;
      final r = await probe(gpu, GpuCheckMode.before);
      expect(r.ok, isTrue, reason: r.message);
      expect(r.gpuEvidence, isFalse);
      expect(
        r.stages.map((s) => s.stage),
        contains(AttestationStage.gpuEvidence),
      );
    });

    test('echter lokaler GPU-Fehler (Nonce) erscheint als fehlgeschlagene '
        'Stufe, nicht als fehlender Nachweis', () async {
      const mismatch = GpuAttestationResult(
        GpuVerdict.failed,
        'GPU-Evidenz bindet die Nonce nicht',
        GpuReason.nonceMismatch,
      );
      final gpu = FakeGpuAttestationVerifier()..localResult = mismatch;
      final r = await probe(gpu, GpuCheckMode.off);
      expect(r.gpuEvidence, isNull);
      final gpuStage = r.stages.singleWhere(
        (s) => s.stage == AttestationStage.gpu,
      );
      expect(gpuStage.outcome, StageOutcome.fail);
      expect(gpuStage.detail, contains('Nonce'));
      expect(
        r.stages.map((s) => s.stage),
        isNot(contains(AttestationStage.gpuEvidence)),
      );
    });

    test(
      'Netzfehler bei der GPU-Evidenz ist keine fehlgeschlagene Stufe',
      () async {
        final gpu = FakeGpuAttestationVerifier()
          ..localResult = const GpuAttestationResult(
            GpuVerdict.unreachable,
            'x',
            GpuReason.unreachable,
          );
        final r = await probe(gpu, GpuCheckMode.off);
        expect(
          r.stages.map((s) => s.stage),
          isNot(contains(AttestationStage.gpu)),
        );
      },
    );
  });
}
