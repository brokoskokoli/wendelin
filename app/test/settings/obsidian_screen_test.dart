import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/obsidian_index.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/platform/platform_ports.dart';
import 'package:wendelin/platform/saf_vault_port.dart';
import 'package:wendelin/ui/settings/obsidian_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart';

const _tree = 'content://tree/primary%3ALeben';

/// Folder picker without Android.
final class FakeVaultAccess extends VaultAccess {
  PickedVault? next = (uri: _tree, name: 'Leben');
  bool access = true;
  final released = <String>[];
  int picks = 0;

  @override
  Future<PickedVault?> pick() async {
    picks++;
    return next;
  }

  @override
  Future<bool> hasAccess(String tree) async => access;

  @override
  Future<void> release(String tree) async => released.add(tree);
}

Future<ProviderContainer> pumpObsidian(
  WidgetTester tester,
  TestEnv env,
  FakeVaultAccess access,
) async {
  setView(tester, const Size(390, 1400));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...env.overrides,
        vaultAccessProvider.overrideWithValue(access),
      ],
      retry: (_, _) => null,
      child: themed(const ObsidianScreen()),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(ObsidianScreen)));
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets(
    'Vault wählen: gespeichert, Integration an und registriert, Index gebaut',
    (tester) async {
      final env = TestEnv();
      env.vault.files
        ..['Wendelin.md'] = '# Wendelin\n\n## Ideen\n'
        ..['Projekte/Garten.md'] = '# Garten\n'
        ..['Journal/2026-10-12.md'] = '- getaucht\n';
      final access = FakeVaultAccess();
      final c = await pumpObsidian(tester, env, access);
      expect(find.text('Kein Vault gewählt'), findsOneWidget);
      expect(c.read(enabledIntegrationsProvider), isNot(contains('obsidian')));

      await tester.tap(find.text('Vault-Ordner wählen'));
      await settle(tester);

      expect(find.text('Leben'), findsOneWidget);
      expect(find.text('Zugriff erteilt'), findsOneWidget);
      final stored = await env.storage.settings.get(AppSettings.obsidian);
      expect(stored!.vaultUri, _tree);
      expect(stored.vaultName, 'Leben');
      expect(c.read(enabledIntegrationsProvider), contains('obsidian'));
      final registry = await c.read(toolRegistryReadyProvider.future);
      expect(
        registry.integrations.singleWhere((i) => i.id == 'obsidian').status,
        IntegrationStatus.active,
      );
      expect(find.text('3 Notizen im Index · aktuell'), findsOneWidget);
      expect((await env.notes.knownFiles()).keys, hasLength(3));
    },
  );

  testWidgets('anderen Ordner wählen gibt den alten frei', (tester) async {
    final env = TestEnv(
      startup: const StartupSettings(
        obsidian: ObsidianPrefs(vaultUri: 'content://alt', vaultName: 'Alt'),
      ),
    );
    final access = FakeVaultAccess();
    final c = await pumpObsidian(tester, env, access);
    await tester.tap(find.text('Anderen Ordner wählen'));
    await settle(tester);
    expect(access.released, ['content://alt']);
    expect(c.read(obsidianPrefsProvider).vaultName, 'Leben');
  });

  testWidgets('Abbruch der Auswahl ändert nichts', (tester) async {
    final env = TestEnv();
    final access = FakeVaultAccess()..next = null;
    final c = await pumpObsidian(tester, env, access);
    await tester.tap(find.text('Vault-Ordner wählen'));
    await settle(tester);
    expect(c.read(obsidianPrefsProvider).hasVault, isFalse);
    expect(c.read(enabledIntegrationsProvider), isNot(contains('obsidian')));
  });

  testWidgets('Zugriff verloren: Hinweis zum neu Wählen', (tester) async {
    final env = TestEnv(
      startup: const StartupSettings(
        obsidian: ObsidianPrefs(vaultUri: _tree, vaultName: 'Leben'),
      ),
    );
    await pumpObsidian(tester, env, FakeVaultAccess()..access = false);
    await settle(tester);
    expect(find.text('Kein Zugriff mehr – Ordner neu wählen'), findsOneWidget);
  });

  testWidgets('Vault entfernen: Rechte frei, Integration aus', (tester) async {
    final env = TestEnv(
      enabled: const {'obsidian'},
      startup: const StartupSettings(
        enabledIntegrations: {'obsidian'},
        obsidian: ObsidianPrefs(vaultUri: _tree, vaultName: 'Leben'),
      ),
    );
    final access = FakeVaultAccess();
    final c = await pumpObsidian(tester, env, access);
    final registry = await c.read(toolRegistryReadyProvider.future);
    expect(registry.status('obsidian'), IntegrationStatus.active);
    await tester.ensureVisible(find.text('Vault entfernen'));
    await tester.tap(find.text('Vault entfernen'));
    await settle(tester);
    await tester.tap(find.text('Entfernen'));
    await settle(tester);
    expect(access.released, [_tree]);
    expect(c.read(obsidianPrefsProvider).hasVault, isFalse);
    expect(c.read(enabledIntegrationsProvider), isNot(contains('obsidian')));
    expect(registry.status('obsidian'), IntegrationStatus.available);
  });

  testWidgets('Tagesnotizen: Vorschau, Speichern, Integration liest sie', (
    tester,
  ) async {
    final env = TestEnv(
      startup: const StartupSettings(
        obsidian: ObsidianPrefs(vaultUri: _tree, vaultName: 'Leben'),
      ),
    );
    final c = await pumpObsidian(tester, env, FakeVaultAccess());
    expect(find.text('Heute: 2026-10-13.md'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Journal');
    await tester.enterText(fields.at(1), 'YYYY/MM/YYYY-MM-DD dddd');
    await tester.enterText(fields.at(2), 'Vorlagen/Tag');
    await tester.pump();
    expect(
      find.text('Heute: Journal/2026/10/2026-10-13 Dienstag.md'),
      findsOneWidget,
    );
    await tester.enterText(fields.at(2), '../aussen');
    await tester.pump();
    expect(find.textContaining('Nicht verwendbar'), findsOneWidget);
    await tester.enterText(fields.at(2), 'Vorlagen/Tag');
    await tester.ensureVisible(find.text('Tagesnotizen speichern'));
    await tester.tap(find.text('Tagesnotizen speichern'));
    await settle(tester);

    const expected = DailyNoteSettings(
      folder: 'Journal',
      format: 'YYYY/MM/YYYY-MM-DD dddd',
      template: 'Vorlagen/Tag',
    );
    expect(c.read(obsidianPrefsProvider).dailyNotes, expected);
    final stored = await env.storage.settings.get(AppSettings.obsidian);
    expect(stored!.dailyNotes, expected);
    final settings = c.read(platformPortsProvider).obsidian!.settings();
    expect(settings.dailyNotes, expected);
    expect(settings.vaultName, 'Leben');
  });

  test('Index in mehreren Läufen bis nichts mehr aussteht', () async {
    final env = TestEnv(
      startup: const StartupSettings(
        obsidian: ObsidianPrefs(vaultUri: _tree, vaultName: 'Leben'),
      ),
    );
    for (var i = 0; i < 450; i++) {
      env.vault.files['Notizen/n$i.md'] = '# Notiz $i\n';
    }
    final c = env.container();
    addTearDown(c.dispose);
    final seen = <IndexProgress>[];
    c.listen(obsidianIndexProvider, (_, p) => seen.add(p));
    final done = await c.read(obsidianIndexProvider.notifier).sync();
    expect(done.total, 450);
    expect(done.running, isFalse);
    expect(done.label, '450 Notizen im Index · aktuell');
    final running = seen.where((p) => p.running && p.indexed > 0).toList();
    expect(running.map((p) => p.pending), [250, 50, 0]);
    expect(running.first.fraction, closeTo(200 / 450, 1e-9));
    expect(running.first.label, 'Index wird aufgebaut: 200 Notizen, noch 250');
  });

  test('Index: ohne Vault nichts, Fehler werden angezeigt', () async {
    final none = TestEnv().container();
    addTearDown(none.dispose);
    final idle = await none.read(obsidianIndexProvider.notifier).sync();
    expect(idle.label, 'Noch nicht aufgebaut');

    final env = TestEnv(
      startup: const StartupSettings(
        obsidian: ObsidianPrefs(vaultUri: _tree, vaultName: 'Leben'),
      ),
    );
    env.vault.failNext(
      'list',
      const PortException(PortErrorKind.permissionDenied, 'Kein Zugriff'),
    );
    final c = env.container();
    addTearDown(c.dispose);
    final p = await c.read(obsidianIndexProvider.notifier).sync();
    expect(p.label, 'Index unvollständig: Kein Zugriff');
  });

  test('ObsidianPrefs: JSON hin und zurück, Kaputtes wird Standard', () {
    const prefs = ObsidianPrefs(
      vaultUri: _tree,
      vaultName: 'Leben',
      dailyNotes: DailyNoteSettings(
        folder: 'Journal',
        format: 'DD.MM.YYYY',
        template: 'T',
      ),
    );
    expect(ObsidianPrefs.fromJson(prefs.toJson()), prefs);
    expect(
      ObsidianPrefs.fromJson(const {'vaultUri': 3, 'dailyNotes': 'x'}),
      const ObsidianPrefs(),
    );
    expect(prefs.withVault(null, null).hasVault, isFalse);
    expect(prefs.withVault(null, null).dailyNotes, prefs.dailyNotes);
  });

  test('Einstellungen der Integration: Name und Sprache', () {
    expect(obsidianSettingsOf(const ObsidianPrefs(), 'de').vaultName, isNull);
    const prefs = ObsidianPrefs(vaultUri: _tree);
    expect(obsidianSettingsOf(prefs, 'de').vaultName, 'Vault');
    expect(obsidianSettingsOf(prefs, 'fr').locale, 'fr');
    expect(obsidianSettingsOf(prefs, 'en').locale, 'en');
    expect(obsidianSettingsOf(prefs, 'it').locale, 'de');
  });
}
