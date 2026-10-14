import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Kleiner, unaufdringlicher Hinweis: Tool-Argumente sind bei Phala nicht
/// Ende-zu-Ende-verschlüsselt, sondern nur über das gepinnte TLS geschützt
/// (ADR 0018). Steht immer im Prüfprotokoll und an einer Phala-Antwort nur,
/// wenn Tools gesendet oder Tool-Aufrufe empfangen wurden.
class ToolTlsHint extends StatelessWidget {
  /// Erstellt den Hinweis.
  const ToolTlsHint({super.key});

  /// Der Text des Hinweises.
  static const text = 'Tool-Argumente nur über gepinntes TLS geschützt';

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: WSpace.xs),
    child: Text(text, style: WText.caption),
  );
}
