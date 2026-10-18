import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/theme/app_theme.dart';

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
  await testMain();
}
