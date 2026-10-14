// WP55: Auswahl „Sprechfassung“ (Golden, nur macOS aktualisieren).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/settings/voice_spoken_section.dart';
import 'package:wendelin_core/wendelin_core.dart' show SpokenVersion;
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'onboarding_settings_goldens_test.dart' show pumpGoldenScreen;

void main() {
  for (final level in [SpokenVersion.always, SpokenVersion.checked]) {
    testWidgets('Golden Sprechfassung ${level.name}', tags: ['golden'], (
      tester,
    ) async {
      await pumpGoldenScreen(
        tester,
        TestEnv(),
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SpokenVersionSection(
              settings: VoiceSettings(spokenVersion: level),
              change: (_) {},
            ),
          ),
        ),
      );
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/sprechfassung_${level.name}.png'),
      );
    });
  }
}
