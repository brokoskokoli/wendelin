import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'gen/app_localizations.dart';
import 'gen/app_localizations_de.dart';

export 'gen/app_localizations.dart';

/// Values of the UI language setting.
const uiLanguageSystem = 'system';

/// Delegates for `MaterialApp.localizationsDelegates`.
const List<LocalizationsDelegate<Object?>> wendelinLocalizationsDelegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// Locale for the stored [code]; `null` follows the system.
Locale? uiLocaleFor(String code) => AppLocalizations.supportedLocales
    .where((l) => l.languageCode == code)
    .firstOrNull;

/// Picks the locale for the system locales [locales]: the first supported
/// language, English otherwise.
Locale resolveUiLocale(List<Locale>? locales, Iterable<Locale> supported) {
  for (final l in locales ?? const <Locale>[]) {
    for (final s in supported) {
      if (s.languageCode == l.languageCode) return s;
    }
  }
  return const Locale('en');
}

/// Access to the texts. Without localizations in the tree (plain widget
/// tests) the German texts are used.
extension WendelinL10n on BuildContext {
  /// The texts in the language of the app.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsDe();
}

/// [value] with one decimal and the decimal separator of [l]'s language
/// ('1,5' in German and French, '1.5' in English).
String decimal1(AppLocalizations l, double value) {
  final s = value.toStringAsFixed(1);
  return l.localeName == 'en' ? s : s.replaceAll('.', ',');
}
