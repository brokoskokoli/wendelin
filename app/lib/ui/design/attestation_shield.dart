import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'check_status.dart';

/// Kleines Schild unter einer TEE-Antwort: [CheckStatusIcon] (Farbe + Form)
/// und ein kurzer Text („geprüft“, „wird geprüft“, „Prüfung
/// fehlgeschlagen“). Mit [onTap] öffnet es den Protokolleintrag.
class AttestationShield extends StatelessWidget {
  /// Erstellt das Schild.
  const AttestationShield({
    super.key,
    required this.status,
    required this.label,
    this.onTap,
  });

  /// Status (ok, pending, failed).
  final CheckStatus status;

  /// Kurztext, auch für Screenreader.
  final String label;

  /// Öffnet den Protokolleintrag.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: onTap == null
        ? 'TEE-Prüfung: $label'
        : 'TEE-Prüfung: $label. Tippen für das Prüfprotokoll.',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WRadius.small),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: WSize.touchMin),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: WSpace.xs6,
          children: [
            CheckStatusIcon(
              status,
              size: WSize.statusIconSmall,
              semanticLabel: label,
            ),
            Text(label, style: WText.caption.copyWith(color: status.color)),
          ],
        ),
      ),
    ),
  );
}
