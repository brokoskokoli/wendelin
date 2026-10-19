import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'icons.dart';

/// Runder Senden-Knopf neben dem Textfeld (Größe wie der kompakte
/// Mikrofon-Knopf, den er ersetzt, solange Text im Feld steht).
class SendButton extends StatelessWidget {
  /// Erstellt den Knopf.
  const SendButton({super.key, required this.onPressed});

  /// Sendet den Text.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    // Tooltip und Semantics-Label in der App-Sprache.
    tooltip: context.l10n.send,
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
