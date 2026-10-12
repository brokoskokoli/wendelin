import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/theme/app_theme.dart';

/// Lädt die gebündelten Schriften, damit Goldens echte Glyphen zeigen.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final family in WFonts.files.entries) {
    final loader = FontLoader(family.key);
    for (final file in family.value) {
      loader.addFont(rootBundle.load(file));
    }
    await loader.load();
  }
  await testMain();
}
