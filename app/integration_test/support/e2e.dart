import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/app.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/main.dart' show loadDeviceInfo;
import 'package:wendelin/platform/device_calendar_port.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// The app as `main.dart` builds it, with a fresh in-memory database and
/// in-memory secrets, but the **real device ports** (calendar channel, SAF
/// channel, clipboard, alarm intents). [config] replaces the stored
/// provider profiles (e.g. the scripted demo provider on the real device
/// ports); `null` reads the stored profiles as in production.
final class E2eApp {
  /// Creates the environment.
  E2eApp({
    this.startup = const StartupSettings(enabledIntegrations: {'calendar'}),
    this.config,
    this.clock,
    this.extraOverrides = const [],
    this._storage,
  });

  /// Fixed time of the app (agent, demo provider, undo); `null` = system.
  final Clock? clock;

  /// Settings at start.
  final StartupSettings startup;

  /// Provider configuration; `null` = from the stored profiles.
  final ProviderConfig? Function(Clock clock)? config;

  /// Further overrides.
  final List<Override> extraOverrides;

  final WendelinStorage? _storage;

  /// Local database: the one given to the constructor (e.g. the app's
  /// database on the device, closed by the test), otherwise in memory
  /// (nothing stays on the device) with the same [clock] as the app,
  /// otherwise session times would not match.
  late final WendelinStorage storage =
      _storage ?? openInMemoryStorage(clock: clock ?? const SystemClock());

  /// Secrets (in memory).
  final InMemorySecretStore secrets = InMemorySecretStore();

  /// Pumps the app and returns its container.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Widget child = const WendelinApp(),
  }) async {
    if (_storage == null) addTearDown(storage.close);
    final device = await loadDeviceInfo();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          storageProvider.overrideWithValue(storage),
          startupProvider.overrideWithValue(startup),
          deviceInfoProvider.overrideWithValue(device),
          secretStoreProvider.overrideWithValue(secrets),
          if (clock case final c?) clockProvider.overrideWithValue(c),
          if (config case final c?)
            storedProviderConfigProvider.overrideWith(
              (ref) async => c(ref.watch(clockProvider)),
            ),
          ...extraOverrides,
        ],
        child: child,
      ),
    );
    await tester.pump();
    return ProviderScope.containerOf(
      tester.element(find.byType(child.runtimeType)),
    );
  }
}

/// Fixed „now“ of the device tests: Tuesday, 12 March 2030, 08:00 local
/// time – far from real events and from a DST change; „morgen“ is
/// [e2eTomorrow].
final e2eNow = DateTime(2030, 3, 12, 8);

/// The day after [e2eNow].
final e2eTomorrow = DateTime(2030, 3, 13);

/// Pumps until [finder] finds something or [timeout] passes (real time:
/// device channels and streamed answers are asynchronous).
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      final texts = find
          .byType(RichText, skipOffstage: false)
          .evaluate()
          .map((e) => (e.widget as RichText).text.toPlainText())
          .where((t) => t.trim().isNotEmpty);
      fail(
        'Nicht erschienen nach $timeout: $finder\n'
        'Sichtbare Texte: ${texts.join(' | ')}',
      );
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Waits until no request is running (the composer accepts input again).
Future<void> waitIdle(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  final running = find.byWidgetPredicate(
    (w) => w is MicButton && w.state == MicState.thinking,
  );
  while (running.evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(end)) fail('Anfrage läuft noch nach 30 s');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Waits until idle, types [text] into the input field and sends it.
Future<void> send(WidgetTester tester, String text) async {
  await waitIdle(tester);
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pump();
  expect(
    tester.widget<TextField>(find.byType(TextField)).controller!.text,
    isEmpty,
    reason: 'Nachricht wurde nicht angenommen',
  );
}

/// Waits up to [timeout] for the calendar permission (granted by the
/// runner script with `adb shell pm grant`, see `tool/e2e_android.sh`).
Future<void> expectCalendarPermission(
  DeviceCalendarPort port, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (!await port.hasPermission()) {
    if (DateTime.now().isAfter(end)) {
      fail(
        'Keine Kalender-Berechtigung. Vorab: adb shell pm grant app.wendelin '
        'android.permission.READ_CALENDAR (und WRITE_CALENDAR)',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

/// Pumps [duration] in small steps (lets sheet animations finish; no
/// `pumpAndSettle`, the thinking indicator animates while a request runs).
Future<void> pumpFor(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 800),
]) async {
  for (
    var t = Duration.zero;
    t < duration;
    t += const Duration(milliseconds: 50)
  ) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// All audit entries of [app] as one text (kind and payload per entry).
Future<String> auditText(E2eApp app) async => [
  for (final e in await app.storage.audit.query())
    '${e.kind.name} ${e.payload}',
].join('\n');

/// Live tests: the Anthropic key that `tool/e2e_android.sh` (with
/// `WENDELIN_LIVE=1`) puts into the private app data via `run-as`. Read
/// and deleted at once; afterwards it only lives in memory.
Future<String> takeLiveKey() async {
  final file = File('/data/user/0/app.wendelin/files/live_anthropic.key');
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (!file.existsSync()) {
    if (DateTime.now().isAfter(end)) fail('Key-Datei kam nicht an');
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final key = file.readAsStringSync().trim();
  file.deleteSync();
  return key;
}
