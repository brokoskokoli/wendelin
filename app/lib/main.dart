import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ui/design/gallery.dart';
import 'ui/design/logo.dart';
import 'ui/theme/app_theme.dart';

// Vorläufig: Debug zeigt die Design-Galerie, Release einen Platzhalter.
// Die echte Verdrahtung folgt in WP08.
void main() {
  registerFontLicenses();
  runApp(const MainApp());
}

/// Wurzel-Widget der App.
class MainApp extends StatelessWidget {
  /// Erstellt die App; [showGallery] überschreibt die Wahl nach Build-Modus.
  const MainApp({super.key, this.showGallery = kDebugMode});

  /// Zeigt die Design-Galerie statt des Platzhalters.
  final bool showGallery;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wendelin',
      theme: buildWendelinTheme(),
      home: showGallery ? const DesignGallery() : const PlaceholderHome(),
    );
  }
}

/// Platzhalter-Startseite für Release-Builds bis WP08.
class PlaceholderHome extends StatelessWidget {
  /// Erstellt den Platzhalter.
  const PlaceholderHome({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: WendelinLockup()));
}
