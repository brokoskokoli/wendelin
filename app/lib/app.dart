import 'package:flutter/material.dart';

import 'ui/onboarding/onboarding_screen.dart';
import 'ui/routes.dart';
import 'ui/screens/main_screen.dart';
import 'ui/theme/app_theme.dart';

/// Root widget (inside a `ProviderScope`). Until the onboarding is done it
/// shows the onboarding instead of [home].
class WendelinApp extends StatelessWidget {
  /// Creates the app.
  const WendelinApp({super.key, this.home = const MainScreen()});

  /// Start screen (tests may replace it).
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Wendelin',
    debugShowCheckedModeBanner: false,
    theme: buildWendelinTheme(),
    home: StartGate(home: home),
    routes: buildAppRoutes(),
  );
}
