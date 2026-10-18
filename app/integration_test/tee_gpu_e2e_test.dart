// Device test (WP82): GPU check per provider profile with the TEE fixture
// gateway (no GPU evidence in its report): mode „Vorher“ in the profile blocks
// the request with the card/dialog „Kein GPU-Nachweis“ (main chat and
// overlay), „Ohne GPU-Prüfung senden“ sends once, a profile without the
// setting is not affected, the old global `tee.gpuCheck` migrates into the
// TEE profiles. Runs via `tool/e2e_android.sh` (emulator only).

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/app.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/attestation_providers.dart';
import 'package:wendelin/di/gpu_check_migration.dart';
import 'package:wendelin/platform/attest/attest_backend.dart';
import 'package:wendelin/platform/attest/collateral_cache.dart';
import 'package:wendelin/platform/attest/pcs_collateral_client.dart';
import 'package:wendelin/platform/attest/rust_attestation_crypto.dart';
import 'package:wendelin/ui/overlay/assistant_overlay.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/fakes.dart';

import 'support/e2e.dart';
import 'support/receipt_substitute.dart';
import 'support/tee_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<(E2eApp, FixtureGateway, ProviderContainer)> start(
    WidgetTester tester, {
    Map<String, String?> profiles = const {'phala': null},
    String defaultId = 'phala',
    Widget child = const WendelinApp(),
  }) async {
    final gateway = FixtureGateway();
    final backend = await FrbAttestBackend.init();
    final tmp = Directory.systemTemp.createTempSync('tee-app-e2e');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final app = E2eApp(
      extraOverrides: [
        // The production factory builds the provider; only the transport
        // (recorded gateway), the clock/nonce of the recording and the
        // collateral source (recorded Intel PCS answers) are replaced.
        attestationTransportProvider.overrideWithValue(
          AttestationTransport(
            client: gateway.client,
            pinnedClient: gateway.pinned,
            settings: HttpSettings(clock: FixedClock(probeNow)),
            nonceSource: () => probeNonce,
          ),
        ),
        attestationCryptoProvider.overrideWith(
          (ref) async => ReceiptSignatureSubstitute(
            RustAttestationCrypto(
              backend: backend,
              pcs: PcsCollateralClient(
                client: pcsFixtureClient(),
                backend: backend,
              ),
              cache: CollateralCache(dir: tmp, now: () => probeNow),
              clock: () => probeNow,
            ),
            gateway.e2ee,
          ),
        ),
      ],
    );
    for (final e in profiles.entries) {
      await app.storage.providerProfiles.save(
        ProviderProfile(
          id: e.key,
          name: 'Phala ${e.key}',
          type: ProviderType.openaiCompatible,
          baseUrl: 'https://api.redpill.ai/v1',
          defaultModel: 'z-ai/glm-5.3-flash',
          privacy: PrivacyLevel.tee,
          authMethod: const ApiKeyAuth('provider.phala.apiKey'),
          options: {
            'attestation': 'phala',
            'teeModelsOnly': true,
            if (e.value != null) gpuCheckOption: e.value,
          },
        ),
      );
    }
    await app.storage.providerProfiles.setDefault(defaultId);
    await app.secrets.write('provider.phala.apiKey', 'e2e-key');
    final c = await app.pump(tester, child: child);
    return (app, gateway, c);
  }

  const answer = 'Ruhig: 0,4 m Welle.';

  testWidgets('Vorher im Profil, Hauptchat: nichts gesendet, Dialog, einmal '
      'ohne Prüfung senden', (tester) async {
    final (app, gateway, c) = await start(
      tester,
      profiles: {'phala': 'before'},
    );
    await send(tester, 'Wie wird das Meer morgen?');
    await pumpUntil(tester, find.text('Kein GPU-Nachweis'));
    expect(gateway.chats, 0, reason: 'Anfrage nicht gesendet');
    expect(find.text('Ohne GPU-Prüfung senden'), findsOneWidget);
    await tester.tap(find.text('Ohne GPU-Prüfung senden'));
    await pumpUntil(tester, find.textContaining(answer));
    expect(gateway.chats, 1);
    // Only this request: the next one is blocked again; cancel leaves it.
    await send(tester, 'Noch eine Frage');
    await pumpUntil(tester, find.text('Kein GPU-Nachweis'));
    await tester.tap(find.text('Abbrechen'));
    await tester.pump(const Duration(seconds: 1));
    expect(gateway.chats, 1);
    expect(c.read(attestationHubProvider).modeOf('phala'), GpuCheckMode.before);
    final p = (await app.storage.providerProfiles.list()).single;
    expect(gpuModeOf(p), GpuCheckMode.before);
  });

  testWidgets('Profil ohne Einstellung bleibt unberührt (Standard aus)', (
    tester,
  ) async {
    final (_, gateway, c) = await start(
      tester,
      profiles: {'phala': 'before', 'phala2': null},
      defaultId: 'phala2',
    );
    await send(tester, 'Wie wird das Meer morgen?');
    await pumpUntil(tester, find.textContaining(answer));
    expect(gateway.chats, 1);
    expect(find.text('Kein GPU-Nachweis'), findsNothing);
    expect(c.read(attestationHubProvider).modeOf('phala2'), GpuCheckMode.off);
  });

  testWidgets('Overlay: Karte „Kein GPU-Nachweis“, einmal ohne Prüfung '
      'senden', (tester) async {
    final (_, gateway, c) = await start(
      tester,
      profiles: {'phala': 'before'},
      child: const AssistantOverlayApp(autoStart: false),
    );
    final agent = c.read(agentControllerProvider.notifier);
    agent.submit(UserInput(text: 'Wie wird das Meer morgen?')).listen((_) {});
    await pumpUntil(tester, find.text('Kein GPU-Nachweis'));
    expect(gateway.chats, 0);
    expect(find.byKey(const ValueKey('gpuBlockCard')), findsOneWidget);
    // The sheet slides in; tap only when it stands still.
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Ohne GPU-Prüfung senden'));
    await pumpUntil(tester, find.textContaining(answer));
    expect(gateway.chats, 1);
    expect(find.text('Kein GPU-Nachweis'), findsNothing);
    agent.submit(UserInput(text: 'Noch eine')).listen((_) {});
    await pumpUntil(tester, find.text('Kein GPU-Nachweis'));
    expect(gateway.chats, 1);
  });

  testWidgets('Migration: globales tee.gpuCheck wandert in die TEE-Profile', (
    tester,
  ) async {
    final storage = openInMemoryStorage(clock: const SystemClock());
    addTearDown(storage.close);
    ProviderProfile profile(String id, PrivacyLevel privacy) => ProviderProfile(
      id: id,
      name: id,
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://example.invalid/v1',
      defaultModel: 'm',
      privacy: privacy,
      authMethod: const ApiKeyAuth('k'),
      options: privacy == PrivacyLevel.tee
          ? const {'attestation': 'phala'}
          : const {},
    );
    await storage.providerProfiles.save(profile('tee', PrivacyLevel.tee));
    await storage.providerProfiles.save(profile('plain', PrivacyLevel.eu));
    await storage.settings.set(AppSettings.legacyGpuCheck, 'before');
    await migrateGlobalGpuCheck(storage.settings, storage.providerProfiles);
    final byId = {
      for (final p in await storage.providerProfiles.list()) p.id: p,
    };
    expect(gpuModeOf(byId['tee']!), GpuCheckMode.before);
    expect(byId['plain']!.options.containsKey(gpuCheckOption), isFalse);
    expect(await storage.settings.get(AppSettings.legacyGpuCheck), isNull);
  });
}
