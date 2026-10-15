// WP66: Untermenü „Stimmen“ (Golden, nur macOS aktualisieren).

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/settings/voice_voices_screen.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart' show goldenKey;
import 'onboarding_settings_goldens_test.dart' show pumpGoldenScreen;

void main() {
  testWidgets('Golden Stimmen', tags: ['golden'], (tester) async {
    final env = TestEnv();
    env.speechModels.installed.addAll([
      'tts-de-thorsten',
      'tts-de-kerstin',
      'tts-fr-siwis',
    ]);
    await pumpGoldenScreen(tester, env, const VoiceVoicesScreen());
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/stimmen.png'),
    );
  });
}
