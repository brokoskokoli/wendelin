import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Placeholder of a settings area that is still being built (M3: routing,
/// MCP servers, HTTP tools). WP26–WP28 replace the route targets in
/// `app.dart` with their screens.
class ComingSoonScreen extends StatelessWidget {
  /// Creates the placeholder for the area [title].
  const ComingSoonScreen({super.key, required this.title, required this.what});

  /// Area title.
  final String title;

  /// What the area will offer.
  final String what;

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: title,
    intro: what,
    children: [
      SectionCard(
        children: [
          SettingsRow(
            title: context.l10n.comingSoonM3,
            detail: context.l10n.comingSoonInProgress,
          ),
        ],
      ),
    ],
  );
}
