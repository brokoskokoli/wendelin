import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'icons.dart';

/// Runder Senden-Knopf neben dem Textfeld (Größe wie der kompakte
/// Mikrofon-Knopf, den er ersetzt, solange Text im Feld steht).
class SendButton extends StatelessWidget {
  /// Erstellt den Knopf.
  const SendButton({super.key, required this.onPressed});

  /// Sendet den Text.
  final VoidCallback onPressed;

  /// Tooltip und Semantics-Label.
  static const label = 'Senden';

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    icon: const WIcon(
      WIcons.send,
      size: WSize.micIconCompact,
      color: WColors.onAccent,
    ),
    style: IconButton.styleFrom(
      fixedSize: const Size.square(WSize.micButtonCompact),
      padding: EdgeInsets.zero,
      backgroundColor: WColors.accent,
      shape: const CircleBorder(),
    ),
  );
}
