import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Kleiner, unaufdringlicher Hinweis: Tool-Argumente sind bei Phala nicht
/// Ende-zu-Ende-verschlüsselt, sondern nur über das gepinnte TLS geschützt
/// (ADR 0018). Steht immer im Prüfprotokoll und an einer Phala-Antwort nur,
/// wenn Tools gesendet oder Tool-Aufrufe empfangen wurden.
class ToolTlsHint extends StatelessWidget {
  /// Erstellt den Hinweis; [encrypted] für Anbieter, die auch Tools
  /// Ende-zu-Ende verschlüsseln (NEAR AI, ADR 0019).
  const ToolTlsHint({super.key, this.encrypted = false});

  /// Tools sind Ende-zu-Ende-verschlüsselt.
  final bool encrypted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: WSpace.xs),
    child: Text(
      encrypted ? context.l10n.toolTlsEncrypted : context.l10n.toolTlsHint,
      style: WText.caption,
    ),
  );
}
