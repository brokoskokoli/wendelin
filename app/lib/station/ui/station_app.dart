import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/preferences.dart';
import '../../l10n/l10n.dart';
import '../../ui/theme/app_theme.dart';
import 'station_screen.dart';

/// Root widget of the station (Dart entrypoint `stationMain`, started by
/// `StationActivity` over the lock screen). It has no chat, no agent and
/// reports nothing as „chat visible“ (the wake word opens the overlay until
/// WP100).
class StationApp extends ConsumerWidget {
  /// Creates the app.
  const StationApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: 'Wendelin',
    locale: uiLocaleFor(ref.watch(uiLanguageProvider)),
    localizationsDelegates: wendelinLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    localeListResolutionCallback: (l, s) => resolveUiLocale(l, s),
    debugShowCheckedModeBanner: false,
    theme: buildWendelinTheme(),
    // Back never leaves the station; ending asks to unlock (WP99).
    home: const PopScope(canPop: false, child: StationScreen()),
  );
}
