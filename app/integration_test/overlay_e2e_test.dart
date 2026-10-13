// Gerätetest M2 (WP19): Wendelin als Standard-Assistent. Das Skript setzt
// die Rolle (`cmd role add-role-holder`) und öffnet das Overlay mit
// KEYCODE_ASSIST (wie der lange Druck auf die Power-Taste). Das Overlay hört
// eine WAV statt des Mikrofons, Whisper base erkennt sie, ein Skript-Provider
// ergänzt die Tagesnotiz im SAF-Test-Vault (Overlay-Engine, `assistantMain`
// mit `deviceTestOverrides`).
//
// Danach der Prüfpunkt zwei Engines (ADR 0006): Das Overlay hat die
// Datenbank zuerst geöffnet (Kaltstart, es startet den gemeinsamen
// drift-Isolate). Die App öffnet sie danach, das Overlay wird geschlossen,
// und die App schreibt weiter: Anfrage, Verlauf, Audit-Log, Index. Zum
// Schluss: Rolle entzogen → WendelinRecognitionService wieder aus.
//
// Nur mit `WENDELIN_MODELS=<dir> tool/e2e_android.sh
// integration_test/overlay_e2e_test.dart`.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show IsolateNameServer;

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/debug/device_test_overrides.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/main.dart' as app show assistantMain, openAppStorage;
import 'package:wendelin/platform/saf_vault_port.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/e2e.dart';
import 'support/voice_e2e.dart';

const _spoken = '- Zahnarzt angerufen';
const _typed = '- Rezept abholen';

/// The overlay's Dart entrypoint. `AssistantActivity` looks it up in the
/// root library, which in this test build is this file (built with
/// `-Ptarget=integration_test/overlay_e2e_test.dart`, see
/// `tool/e2e_android.sh`): the overlay engine runs the real overlay.
@pragma('vm:entry-point')
Future<void> assistantMain() => app.assistantMain();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Assistent: KEYCODE_ASSIST → Overlay hört WAV → Notiz; zwei Engines',
    (tester) async {
      await waitForDeviceFiles();
      final vault = await pickTestVault();
      final port = vaultPort(vault);
      await resetTestNote(port);
      final e2e = await e2eDirectory();
      addTearDown(() async {
        for (final f in ['overlay.json', 'de-05.wav']) {
          final file = File('${e2e.path}/$f');
          if (file.existsSync()) file.deleteSync();
        }
        if (await port.exists(testDailyNote)) await port.delete(testDailyNote);
        await const VaultAccess().release(vault.uri);
      });

      // 1. Einstellungen für das Overlay in die App-Datenbank, ohne den
      //    gemeinsamen Isolate zu starten (eigene, kurze Verbindung).
      final setup = WendelinStorage(driftDatabase(name: 'wendelin'));
      await setup.settings.set(AppSettings.onboardingDone, true);
      await setup.settings.set(
        AppSettings.integrationEnabled('obsidian'),
        true,
      );
      await setup.settings.set(AppSettings.obsidian, testObsidian(vault));
      await setup.settings.set(
        voiceSettingsKey,
        const VoiceSettings(sttModel: 'whisper-base'),
      );
      await setup.close();

      // 2. Was das Overlay hört und was der Skript-Provider antwortet.
      File(await fixtureWav('de-05')).copySync('${e2e.path}/de-05.wav');
      File('${e2e.path}/overlay.json').writeAsStringSync(
        jsonEncode({
          'audio': 'de-05.wav',
          'turns': [
            {
              'tool': 'obsidian__append_daily_note',
              'arguments': appendArgs(_spoken),
            },
            {'text': 'Steht in deiner Tagesnotiz.'},
          ],
        }),
      );

      // 3. Overlay kalt starten (Rolle, KEYCODE_ASSIST) und warten, bis die
      //    gesprochene Bitte in der Notiz steht.
      // Noch kein gemeinsamer drift-Isolate (Name aus drift_flutter).
      const driftPort = 'drift-db/wendelin';
      expect(IsolateNameServer.lookupPortByName(driftPort), isNull);
      final watch = Stopwatch()..start();
      await askHost('assist');
      final note = await waitForNote(port, (c) => c != testNoteBefore);
      expect(note, testNoteAfter([_spoken]));
      // ignore: avoid_print
      print(
        'M2-Messung Overlay: KEYCODE_ASSIST bis Notiz ergänzt '
        '${watch.elapsedMilliseconds} ms (Whisper base, WAV ≈ 4 s)',
      );

      // 4. Die App öffnet die Datenbank, solange das Overlay läuft: sie
      //    verbindet sich mit dem Isolate, den das Overlay gestartet hat.
      expect(
        IsolateNameServer.lookupPortByName(driftPort),
        isNotNull,
        reason: 'Das Overlay hat den gemeinsamen Isolate gestartet',
      );
      final (storage, startup) = await app.openAppStorage();
      addTearDown(storage.close);
      expect(startup.enabledIntegrations, contains('obsidian'));
      final overlayAudit = await auditOf(storage);
      expect(overlayAudit, contains('obsidian__append_daily_note'));
      expect(overlayAudit, contains('assistant'), reason: 'Auslöser Assistent');

      // 5. Overlay schließen (Zurück): seine Engine endet.
      await askHost('back');
      await Future<void>.delayed(const Duration(seconds: 2));

      // 6. Die App schreibt weiter: Anfrage, Verlauf, Audit-Log, Index.
      final before = (await storage.audit.query()).length;
      final provider = FakeLlmProvider([
        ScriptedTurn.toolCalls([
          ToolCallBlock(
            id: 't1',
            name: 'obsidian__append_daily_note',
            argumentsJson: jsonEncode(appendArgs(_typed)),
          ),
        ]),
        ScriptedTurn.text('Auch notiert.'),
      ]);
      final e2eApp = E2eApp(
        storage: storage,
        startup: startup,
        config: (_) => deviceTestProviderConfig(provider),
      );
      await e2eApp.pump(tester);
      await send(tester, 'Notier noch, dass ich das Rezept abholen muss');
      await pumpUntil(tester, find.text('Auch notiert.'));
      await waitIdle(tester);
      expect(await port.read(testDailyNote), testNoteAfter([_spoken, _typed]));
      final audit = await storage.audit.query();
      expect(audit.length, greaterThan(before), reason: 'Audit-Log schreibt');
      final sessions = await storage.conversations.sessions(limit: 5);
      final texts = [
        for (final s in sessions)
          for (final m in await storage.conversations.messages(s.id))
            jsonEncode(m.message.content.map((b) => '$b').toList()),
      ].join('\n');
      expect(texts, contains('Rezept abholen'), reason: 'Verlauf schreibt');
      // Index-Aufbau der App (Start mit eingeschalteter Integration).
      final end = DateTime.now().add(const Duration(seconds: 30));
      while (!(await storage.notes.knownFiles()).containsKey(testDailyNote)) {
        if (DateTime.now().isAfter(end)) fail('Index ohne die Tagesnotiz');
        await pumpFor(tester, const Duration(milliseconds: 500));
      }

      // 7. Rolle entziehen: der Erkennungsdienst ist wieder aus.
      await askHost('unrole');
      expect(
        File('${e2e.path}/recognizer-state').readAsStringSync().trim(),
        'aus',
      );
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

/// Audit entries of [storage] as one text.
Future<String> auditOf(WendelinStorage storage) async =>
    [for (final e in await storage.audit.query()) '${e.kind.name} ${e.payload}']
        .join('\n');
