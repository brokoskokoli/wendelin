import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:test_api/src/backend/invoker.dart' show Invoker;
// ignore: implementation_imports
import 'package:test_api/src/backend/state.dart' show Result;
import 'package:wendelin/ui/overlay/assistant_overlay.dart';
import 'package:wendelin/ui/theme/app_theme.dart';
import 'package:wendelin/voice/dev_log.dart';
import 'package:wendelin/voice/voice_log.dart';

import 'support/golden_tolerance.dart';

/// Lädt die gebündelten Schriften, damit Goldens echte Glyphen zeigen.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Tests open many in-memory databases on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  for (final family in WFonts.files.entries) {
    final loader = FontLoader(family.key);
    for (final file in family.value) {
      loader.addFont(rootBundle.load(file));
    }
    await loader.load();
  }
  // CI rasterises slightly differently (see golden_tolerance.dart).
  useCiGoldenTolerance();
  // The system language of the tests is German (the texts the tests look
  // for); tests of other languages set the app language explicitly.
  setUp(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.localesTestValue = [
      const Locale('de', 'DE'),
    ];
  });
  _bufferVoiceLog();
  // The overlay tests read their container after the close (WP145 frees it
  // for real in overlay_teardown_test.dart).
  setUp(() => AssistantOverlayScreen.tearDownEngine = (_, _) async {});
  // WP172: the overlay closes itself after the answer (default); tests that
  // need the sheet afterwards switch it off locally.
  setUp(() => AssistantOverlayScreen.closeWhenIdle = true);
  await testMain();
}

/// Puffert `Wendelin/voice:`-Zeilen je Test und gibt sie nur aus, wenn
/// dieser Test rot ist (sonst füllen sie die Fehlerausgabe). Tests, die
/// `voiceLogSink` selbst setzen, behalten ihre Senke.
void _bufferVoiceLog() {
  final buffer = <String>[];
  setUp(() {
    buffer.clear();
    voiceLogSink = buffer.add;
    devLogEnabled = false;
  });
  tearDown(() {
    final result = Invoker.current?.liveTest.state.result;
    if (result == Result.failure || result == Result.error) {
      for (final l in buffer) {
        debugPrint(l);
      }
    }
    buffer.clear();
  });
}
