import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'di/preferences.dart';
import 'l10n/l10n.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/routes.dart';
import 'ui/screens/main_screen.dart';
import 'ui/theme/app_theme.dart';
import 'voice/wake/wake_chat.dart';

/// Root widget (inside a `ProviderScope`). Until the onboarding is done it
/// shows the onboarding instead of [home].
class WendelinApp extends ConsumerWidget {
  /// Creates the app.
  const WendelinApp({super.key, this.home = const MainScreen()});

  /// Start screen (tests may replace it).
  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: 'Wendelin',
    locale: uiLocaleFor(ref.watch(uiLanguageProvider)),
    localizationsDelegates: wendelinLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    localeListResolutionCallback: (l, s) => resolveUiLocale(l, s),
    debugShowCheckedModeBanner: false,
    theme: buildWendelinTheme(),
    home: StartGate(home: home),
    routes: buildAppRoutes(),
    navigatorObservers: [wakeRouteObserver],
  );
}
