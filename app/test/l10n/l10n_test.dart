import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/money.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/l10n/gen/app_localizations_en.dart';
import 'package:wendelin/l10n/gen/app_localizations_fr.dart';
import 'package:wendelin/l10n/l10n.dart';
import 'package:wendelin/ui/routes.dart';
import 'package:wendelin/ui/settings/app_language_screen.dart';
import 'package:wendelin/ui/settings/settings_screen.dart';

import '../settings/integrations_screen_test.dart' show settle;
import '../settings/other_screens_test.dart' show pumpPage;
import '../support/test_env.dart';

Map<String, String> _arb(String lang) {
  final json = jsonDecode(
    File('lib/l10n/app_$lang.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  return {
    for (final e in json.entries)
      if (!e.key.startsWith('@')) e.key: e.value as String,
  };
}

Set<String> _placeholders(String text) => {
  for (final m in RegExp(r'(?<![\w=])\{(\w+)(?:,|\})').allMatches(text))
    m.group(1)!,
}..removeAll(const {'one', 'other', 'zero', 'few', 'many', 'two'});

void main() {
  final de = _arb('de');

  for (final lang in ['en', 'fr']) {
    test('alle Schlüssel liegen auch auf $lang vor, ohne leere Texte', () {
      final other = _arb(lang);
      expect(
        de.keys.toSet().difference(other.keys.toSet()),
        isEmpty,
        reason: 'fehlt in app_$lang.arb',
      );
      expect(
        other.keys.toSet().difference(de.keys.toSet()),
        isEmpty,
        reason: 'überzählig in app_$lang.arb',
      );
      for (final e in other.entries) {
        expect(e.value.trim(), isNotEmpty, reason: '${e.key} ($lang)');
        expect(
          _placeholders(e.value),
          _placeholders(de[e.key]!),
          reason: 'Platzhalter ${e.key} ($lang)',
        );
      }
    });
  }

  test('Übersetzungen sind nicht einfach der deutsche Text', () {
    // Einzelne Wörter und Eigennamen dürfen gleich sein; sonst ist es
    // meist eine vergessene Übersetzung.
    for (final lang in ['en', 'fr']) {
      final other = _arb(lang);
      final same = [
        for (final e in de.entries)
          if (e.value.replaceAll(RegExp(r'\{[^}]*\}'), '').length > 24 &&
              other[e.key] == e.value)
            e.key,
      ];
      expect(same, isEmpty, reason: 'unübersetzt in $lang');
    }
  });

  test('Sprachcodes: System folgt dem Telefon, sonst feste Sprache', () {
    expect(uiLocaleFor('system'), isNull);
    expect(uiLocaleFor('fr'), const Locale('fr'));
    final supported = AppLocalizations.supportedLocales;
    expect(
      resolveUiLocale([const Locale('fr', 'CH')], supported),
      const Locale('fr'),
    );
    expect(
      resolveUiLocale([const Locale('es')], supported),
      const Locale('en'),
    );
    expect(resolveUiLocale(null, supported), const Locale('en'));
  });

  testWidgets('Umschalten wirkt sofort auf die ganze UI und wird gespeichert', (
    tester,
  ) async {
    final env = TestEnv();
    final container = await pumpPage(tester, env, const SettingsScreen());
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(container.read(uiLanguageProvider), 'system');

    await container.read(uiLanguageProvider.notifier).set('en');
    await settle(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Einstellungen'), findsNothing);

    await container.read(uiLanguageProvider.notifier).set('fr');
    await settle(tester);
    expect(find.text('Paramètres'), findsOneWidget);

    // Die Spracheingabe-/Ausgabe-Sprache bleibt unberührt.
    expect(container.read(languageProvider), 'de');
  });

  test('Beträge im Zahlenformat der App-Sprache', () {
    expect(formatUsdFor(AppLocalizationsEn(), 1500000), '\$1.50');
    expect(formatUsdFor(AppLocalizationsFr(), 1500000), '1,50 \$');
    expect(formatUsdFor(AppLocalizationsDe(), 1500000), '1,50 \$');
  });

  test('uiTexts (ohne BuildContext): System und feste Sprache', () async {
    final env = TestEnv();
    final container = env.container();
    addTearDown(container.dispose);
    late AppLocalizations seen;
    final probe = Provider<int>((ref) {
      seen = uiTexts(ref);
      return 0;
    });
    container.read(probe);
    expect(seen.localeName, 'de');
    await container.read(uiLanguageProvider.notifier).set('fr');
    container.invalidate(probe);
    container.read(probe);
    expect(seen.localeName, 'fr');
    expect(seen.agentNoticeCancelled, 'Annulé.');
  });

  testWidgets('Auswahl in den Einstellungen setzt die App-Sprache', (
    tester,
  ) async {
    final container = await pumpPage(tester, TestEnv(), const SettingsScreen());
    await tester.tap(find.text('App-Sprache'));
    await settle(tester);
    await tester.tap(find.text('English'));
    await settle(tester);
    expect(container.read(uiLanguageProvider), 'en');
    expect(find.text('App language'), findsWidgets);
  });

  testWidgets('Sprachnamen sind immer Endonyme (auch in en und fr)', (
    tester,
  ) async {
    for (final code in ['en', 'fr']) {
      final env = TestEnv(startup: StartupSettings(uiLanguage: code));
      await pumpPage(tester, env, const AppLanguageScreen());
      await settle(tester);
      expect(find.text('Deutsch'), findsOneWidget, reason: code);
      expect(find.text('English'), findsOneWidget, reason: code);
      expect(find.text('Français'), findsOneWidget, reason: code);
      expect(find.text('German'), findsNothing);
      expect(find.text('Allemand'), findsNothing);
    }
  });

  testWidgets('gespeicherte Sprache gilt beim Start (Overlay liest dasselbe)', (
    tester,
  ) async {
    final env = TestEnv(startup: const StartupSettings(uiLanguage: 'en'));
    await pumpPage(tester, env, const SettingsScreen());
    expect(find.text('Settings'), findsOneWidget);
    expect(AppRoutes.appLanguage, isNotEmpty);
  });
}
