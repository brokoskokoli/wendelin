import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'check_status.dart';
import 'glyphs.dart';

/// Kleiner Hinweis auf einen ausgeführten Tool-Aufruf im Verlauf
/// (z. B. „✓ weather__marine_forecast“), Mono 12 auf `surface`.
class ToolChip extends StatelessWidget {
  /// Erstellt einen Tool-Chip.
  const ToolChip(this.toolName, {super.key, this.status = CheckStatus.ok});

  /// Tool-Name (`integration__tool`).
  final String toolName;

  /// Ergebnis: ✓ erledigt, ▲ wartet, ✕ fehlgeschlagen.
  final CheckStatus status;

  @override
  Widget build(BuildContext context) {
    final (shape, color) = switch (status) {
      CheckStatus.ok => (GlyphShape.check, WColors.textMuted),
      CheckStatus.pending => (GlyphShape.triangle, WColors.warn),
      CheckStatus.failed => (GlyphShape.cross, WColors.error),
      CheckStatus.neutral => (GlyphShape.ring, WColors.textMuted),
      CheckStatus.info => (GlyphShape.check, WColors.textMuted),
    };
    return Semantics(
      container: true,
      label: context.l10n.toolChipSemantics(
        toolName,
        status.labelOf(context.l10n),
      ),
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: WColors.surface,
            borderRadius: BorderRadius.circular(WRadius.small),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WSpace.s,
              vertical: WSpace.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: WSpace.xs6,
              children: [
                Glyph(shape, color: color),
                Flexible(
                  child: Text(
                    toolName,
                    style: WText.mono,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
