import 'package:flutter/material.dart';

import 'ui/design/gallery.dart';
import 'ui/theme/app_theme.dart';

// Vorläufig: zeigt die Design-Galerie. Die echte Verdrahtung folgt in WP08.
void main() {
  registerFontLicenses();
  runApp(const MainApp());
}

/// Wurzel-Widget der App.
class MainApp extends StatelessWidget {
  /// Erstellt die App.
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wendelin',
      theme: buildWendelinTheme(),
      home: const DesignGallery(),
    );
  }
}
