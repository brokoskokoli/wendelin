import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/ui/settings/voice_screen.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'voice_settings_test.dart' show pumpScreen;

void main() {
  testWidgets('„(empfohlen)“ nur bei Parakeet, nicht bei Whisper', (
    tester,
  ) async {
    final env = TestEnv(startup: const StartupSettings(language: 'fr'));
    env.systemTts.available = false;
    env.speechModels.installed.addAll(['whisper-base', 'silero-vad']);
    await pumpScreen(tester, env, const VoiceScreen());
    String title(SpeechModel m) => '${m.displayName} (empfohlen)';
    expect(find.text(title(SpeechModelCatalog.parakeetV3)), findsOneWidget);
    expect(find.textContaining('(empfohlen)'), findsOneWidget);
    for (final m in [
      SpeechModelCatalog.whisperBase,
      SpeechModelCatalog.whisperSmall,
    ]) {
      expect(find.text(title(m)), findsNothing);
    }
  });
}
