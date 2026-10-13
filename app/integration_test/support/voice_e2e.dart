import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wendelin/debug/device_test_overrides.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/platform/saf_vault_port.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

// Shared parts of the M2 device tests (WP19): speech from WAV files,
// Whisper models and an Obsidian test vault on the emulator. Prepared by
// `tool/e2e_android.sh` with `WENDELIN_MODELS=<dir>` (see there).

/// Whether the runner prepared models and WAVs (`--dart-define`).
const voiceE2e = bool.fromEnvironment('WENDELIN_VOICE_E2E');

/// Folder of the test files in the app data (`files/e2e/`).
Future<Directory> e2eDirectory() async => Directory(
  '${(await getApplicationSupportDirectory()).path}/$deviceTestFolder',
);

/// Path of the WAV fixture [id] (e.g. `de-05`), copied by the runner from
/// `app/test/fixtures/stt/`.
Future<String> fixtureWav(String id) async =>
    '${(await e2eDirectory()).path}/stt/$id.wav';

/// Waits until the runner has copied models and WAVs (`files/e2e/ready`).
Future<void> waitForDeviceFiles() async {
  final ready = File('${(await e2eDirectory()).path}/ready');
  final end = DateTime.now().add(const Duration(minutes: 5));
  while (!ready.existsSync()) {
    if (DateTime.now().isAfter(end)) {
      fail(
        'Modelle/WAVs fehlen: tool/e2e_android.sh mit WENDELIN_MODELS=<dir> '
        'starten',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}

/// Lets the user (here: `tool/e2e_android.sh` via uiautomator) pick the
/// test vault `Documents/WendelinE2E` in the system folder picker.
Future<PickedVault> pickTestVault() async {
  final picked = await const VaultAccess().pick().timeout(
    const Duration(seconds: 90),
    onTimeout: () =>
        fail('Ordnerauswahl nicht bestätigt (tool/e2e_android.sh)'),
  );
  if (picked == null) fail('Ordnerauswahl abgebrochen');
  expect(picked.name, 'WendelinE2E');
  return picked;
}

/// Asks the runner script to do [action] on the device (`assist`: open
/// the overlay with KEYCODE_ASSIST, `back`: close it) and waits until it
/// is done. The script polls `files/e2e/host-request`.
Future<void> askHost(
  String action, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final dir = await e2eDirectory();
  final done = File('${dir.path}/host-done-$action');
  if (done.existsSync()) done.deleteSync();
  File('${dir.path}/host-request').writeAsStringSync(action);
  final end = DateTime.now().add(timeout);
  while (!done.existsSync()) {
    if (DateTime.now().isAfter(end)) fail('Gerät hat „$action“ nicht erledigt');
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  done.deleteSync();
}

/// Daily notes of the test vault: `Tagebuch/YYYY-MM-DD.md`.
const testDailyNotes = DailyNoteSettings(folder: 'Tagebuch');

/// The day the scripted provider writes to (fixed, no clock involved).
const testDay = '2030-03-12';

/// Path of the daily note of [testDay].
const testDailyNote = 'Tagebuch/$testDay.md';

/// The daily note before the request: BOM, CRLF, no final line break –
/// all of it must survive the append byte for byte.
const testNoteBefore =
    '﻿# Dienstag\r\n\r\n## Log\r\n- 08:00 Frühstück\r\n\r\n'
    '## Ideen\r\n- Wendelin testen';

/// [testNoteBefore] after appending [line] under „Log“.
String testNoteAfter(List<String> lines) =>
    '﻿# Dienstag\r\n\r\n## Log\r\n- 08:00 Frühstück\r\n'
    '${[for (final l in lines) '$l\r\n'].join()}\r\n'
    '## Ideen\r\n- Wendelin testen';

/// Arguments of `obsidian__append_daily_note` for [line].
Map<String, Object?> appendArgs(String line) => {
  'text': line,
  'date': testDay,
  'heading': 'Log',
};

/// Obsidian settings of the test vault [vault].
ObsidianPrefs testObsidian(PickedVault vault) => ObsidianPrefs(
  vaultUri: vault.uri,
  vaultName: vault.name,
  dailyNotes: testDailyNotes,
);

/// The vault port of [vault].
SafVaultPort vaultPort(PickedVault vault) =>
    SafVaultPort(tree: () => vault.uri);

/// Writes [testNoteBefore] (replacing an earlier run's note).
Future<void> resetTestNote(SafVaultPort port) async {
  if (await port.exists(testDailyNote)) {
    await port.write(testDailyNote, testNoteBefore);
  } else {
    await port.create(testDailyNote, testNoteBefore);
  }
}

/// Polls the note until [test] holds or [timeout] passes.
Future<String> waitForNote(
  SafVaultPort port,
  bool Function(String content) test, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final end = DateTime.now().add(timeout);
  var content = await port.read(testDailyNote);
  while (!test(content)) {
    if (DateTime.now().isAfter(end)) {
      fail('Notiz nicht wie erwartet nach $timeout:\n$content');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    content = await port.read(testDailyNote);
  }
  return content;
}
