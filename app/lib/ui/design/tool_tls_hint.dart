import 'package:flutter/material.dart';

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

  /// Der Text des Hinweises.
  static const text =
      'Tool-Aufrufe sind über die geprüfte Verbindung bis in die Enklave geschützt, aber nicht zusätzlich verschlüsselt.';

  /// Der Text bei Ende-zu-Ende-verschlüsselten Tools.
  static const encryptedText = 'Tools Ende-zu-Ende-verschlüsselt';

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: WSpace.xs),
    child: Text(encrypted ? encryptedText : text, style: WText.caption),
  );
}
