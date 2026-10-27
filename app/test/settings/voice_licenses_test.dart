import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_settings_providers.dart'
    show speechModelCatalogProvider;
import 'package:wendelin/ui/settings/settings_page.dart' show SettingsRow;
import 'package:wendelin/ui/settings/voice_licenses_screen.dart';
import 'package:wendelin/ui/settings/voice_screen.dart';

import '../support/test_env.dart';
import 'integrations_screen_test.dart' show settle;
import 'voice_settings_test.dart' show pumpScreen;

void main() {
  testWidgets('Sprachseite zeigt nur den Lizenz-Eintrag, Tipp öffnet Liste', (
    tester,
  ) async {
    await pumpScreen(tester, TestEnv(), const VoiceScreen());
    expect(find.textContaining('SIWIS French Speech Synthesis'), findsNothing);
    final row = find.widgetWithText(SettingsRow, 'Lizenzen der Sprachmodelle');
    await tester.scrollUntilVisible(row, 200);
    await tester.tap(row);
    await settle(tester);
    expect(find.byType(VoiceLicensesScreen), findsOneWidget);
    final catalog = ProviderScope.containerOf(
      tester.element(find.byType(VoiceLicensesScreen)),
    ).read(speechModelCatalogProvider);
    for (final m in catalog.models) {
      await tester.scrollUntilVisible(find.text(m.displayName), 200);
      expect(find.text(m.displayName), findsOneWidget);
    }
  });

  testWidgets('Lizenzseite nennt Parakeet, Canary, Siwis und Kokoro', (
    tester,
  ) async {
    await pumpScreen(tester, TestEnv(), const VoiceLicensesScreen());
    for (final t in [
      'Parakeet TDT 0.6B v3“ von NVIDIA, CC BY 4.0',
      'Canary 180M Flash“ von NVIDIA, CC BY 4.0',
      'Kokoro-82M (hexgrad, Apache-2.0)',
      'SIWIS French Speech Synthesis',
      'CC0 (Thorsten-Voice)',
    ]) {
      await tester.scrollUntilVisible(find.textContaining(t).first, 200);
      expect(find.textContaining(t), findsWidgets);
    }
  });
}
