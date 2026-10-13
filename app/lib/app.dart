import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ui/design/gallery.dart';
import 'ui/routes.dart';
import 'ui/screens/main_screen.dart';
import 'ui/screens/settings_placeholder.dart';
import 'ui/theme/app_theme.dart';

/// Root widget (inside a `ProviderScope`).
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
    home: home,
    routes: {
      AppRoutes.settings: (_) => const SettingsPlaceholderScreen(),
      AppRoutes.providerSetup: (_) => const ProviderSetupPlaceholderScreen(),
      if (kDebugMode) AppRoutes.gallery: (_) => const DesignGallery(),
    },
  );
}
