import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'icons.dart';

/// Abgesetzter Info-Text auf Einstellungsseiten: Fläche `surfaceRaised`,
/// ⓘ links, Text 14 sekundär.
class InfoBox extends StatelessWidget {
  /// Erstellt eine Info-Box.
  const InfoBox(this.text, {super.key});

  /// Erläuterung.
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: WColors.surfaceRaised,
      borderRadius: BorderRadius.circular(WRadius.card),
    ),
    child: Padding(
      padding: const EdgeInsets.all(WSpace.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: WSpace.m,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: WSpace.xxs),
            child: WIcon(
              WIcons.info,
              size: WSize.iconSmall,
              color: WColors.textMuted,
            ),
          ),
          Expanded(child: Text(text, style: WText.info)),
        ],
      ),
    ),
  );
}
