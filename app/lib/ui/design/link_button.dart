import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'icons.dart';

/// Linksbündiger Knopf für Sprünge aus der App heraus (Systemeinstellungen,
/// Webseite): Outlined, ↗ hinter dem Text, mindestens 44 hoch, seitlicher
/// Abstand `WSpace.l` (Text fluchtet mit SettingsRow-Text).
class LinkButton extends StatelessWidget {
  /// Erstellt den Knopf.
  const LinkButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.external = true,
  });

  /// Beschriftung.
  final String label;

  /// Aktion.
  final VoidCallback? onPressed;

  /// ↗ zeigen (Sprung aus der App); `false` für Wechsel innerhalb der App.
  final bool external;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: WColors.link,
        minimumSize: const Size(WSize.touchMin, WSize.touchMin),
        // Text fluchtet mit dem Zeilentext der Karte darüber.
        padding: const EdgeInsets.symmetric(horizontal: WSpace.l),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: WSpace.s,
        children: [
          Flexible(child: Text(label)),
          if (external)
            const WIcon(
              WIcons.external,
              size: WSize.iconSmall,
              color: WColors.link,
            ),
        ],
      ),
    ),
  );
}
