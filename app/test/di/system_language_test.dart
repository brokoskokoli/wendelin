import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/l10n/l10n.dart';
import 'package:wendelin/voice/recognizer_config.dart';
import 'package:wendelin_storage/fakes.dart';

import '../support/test_env.dart';

/// WP174: without a stored choice, display, speech input and speech output
/// follow the system language (de/en/fr, anything else English).
void main() {
  Future<ProviderContainer> containerFor(
    List<Locale> locales, {
    String? storedLanguage,
    String? storedUi,
  }) async {
    final storage = openInMemoryStorage();
    if (storedLanguage != null) {
      await storage.settings.set(AppSettings.language, storedLanguage);
    }
    if (storedUi != null) {
      await storage.settings.set(AppSettings.uiLanguage, storedUi);
    }
    final startup = await StartupSettings.load(
      storage.settings,
      const [],
      systemLocales: locales,
    );
    final env = TestEnv(storage: storage, startup: startup);
    final c = ProviderContainer(
      overrides: env.overrides,
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    return c;
  }

  for (final (system, expected) in const [
    ('de', 'de'),
    ('en', 'en'),
    ('fr', 'fr'),
    ('es', 'en'),
    ('ja', 'en'),
  ]) {
    test(
      'Systemsprache $system: Eingabe, Ausgabe und Anzeige $expected',
      () async {
        final c = await containerFor([Locale(system)]);
        // Speech output and prompts read this provider (voice_controller).
        expect(c.read(languageProvider), expected);
        // Speech input („Wie die App“ is the default of the STT language).
        await c.read(voiceSettingsProvider.future);
        expect(c.read(recognizerConfigProvider)?.language, expected);
        // Display: stays „system“ and resolves to the same language.
        expect(c.read(uiLanguageProvider), 'system');
        final binding = TestWidgetsFlutterBinding.ensureInitialized();
        binding.platformDispatcher.localesTestValue = [Locale(system)];
        addTearDown(binding.platformDispatcher.clearLocalesTestValue);
        late AppLocalizations seen;
        final probe = Provider<int>((ref) {
          seen = uiTexts(ref);
          return 0;
        });
        c.read(probe);
        expect(seen.localeName, expected);
      },
    );
  }

  test('gespeicherte Wahl gewinnt über die Systemsprache', () async {
    final c = await containerFor(
      const [Locale('fr')],
      storedLanguage: 'de',
      storedUi: 'en',
    );
    expect(c.read(languageProvider), 'de');
    expect(c.read(uiLanguageProvider), 'en');
  });
}
