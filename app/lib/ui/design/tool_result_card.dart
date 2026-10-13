import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'icons.dart';

/// Ergebnis eines schreibenden Tools mit „Rückgängig“ und Restzeit.
///
/// Ohne [onUndo] oder mit abgelaufener Restzeit entfällt der Button.
class ToolResultCard extends StatelessWidget {
  /// Erstellt eine Ergebniskarte.
  const ToolResultCard({
    super.key,
    required this.title,
    required this.detail,
    required this.toolName,
    this.onUndo,
    this.undoRemaining,
    this.undone = false,
    this.icon = WIcons.task,
  });

  /// Was passiert ist („Termin angelegt“).
  final String title;

  /// Einzelheiten („Tauchen · Di 13.10. · 10:00–11:00 · Privat“).
  final String detail;

  /// Tool-Name in Mono.
  final String toolName;

  /// Rückgängig-Aktion.
  final VoidCallback? onUndo;

  /// Verbleibende Zeit für „Rückgängig“ (aufgerundet auf Sekunden).
  final Duration? undoRemaining;

  /// Zustand „rückgängig“: Inhalt gedämpft und durchgestrichen, statt des
  /// Buttons der Hinweis [undoneLabel].
  final bool undone;

  /// Hinweis im Zustand [undone].
  static const undoneLabel = 'Rückgängig gemacht';

  /// Icon der Integration.
  final WIconData icon;

  /// Restsekunden, aufgerundet; 0 wenn abgelaufen oder nicht gesetzt.
  int get undoSeconds {
    final r = undoRemaining;
    if (r == null || r <= Duration.zero) return 0;
    return (r.inMilliseconds + 999) ~/ 1000;
  }

  TextStyle _struck(TextStyle style) =>
      undone ? style.copyWith(decoration: TextDecoration.lineThrough) : style;

  @override
  Widget build(BuildContext context) {
    final seconds = undoSeconds;
    final canUndo = onUndo != null && seconds > 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WColors.surface,
        borderRadius: BorderRadius.circular(WRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(WSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WSpace.m,
          children: [
            Row(
              spacing: WSpace.m,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: WColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(WRadius.tile),
                  ),
                  child: SizedBox.square(
                    dimension: WSize.iconTile,
                    child: Center(child: WIcon(icon)),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: WSpace.xxs,
                    children: [
                      Text(title, style: _struck(WText.label)),
                      Text(detail, style: _struck(WText.detail)),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    toolName,
                    style: WText.mono,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (undone)
                  Text(
                    undoneLabel,
                    style: WText.caption,
                    semanticsLabel: undoneLabel,
                  )
                else if (canUndo)
                  OutlinedButton(
                    onPressed: onUndo,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: WSpace.l),
                    ),
                    child: Text(
                      'Rückgängig · $seconds s',
                      semanticsLabel: 'Rückgängig, noch $seconds Sekunden',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
