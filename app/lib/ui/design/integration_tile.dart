import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../theme/app_theme.dart';
import 'glyphs.dart';
import 'icons.dart';
import 'privacy_chip.dart';
import 'w_switch.dart';

/// Zeile einer Integration in der Liste (innerhalb einer [SectionCard]).
///
/// Darstellung je [IntegrationStatus] (wendelin_core): `active` Schalter an +
/// grüner Punkt, `available` Schalter aus, `setupRequired` gelbes Dreieck +
/// Button, `error` rotes Quadrat + Button, `unavailable` gedämpft (0.55) mit
/// optionalem Store-Link.
class IntegrationTile extends StatelessWidget {
  /// Erstellt eine Integrationszeile.
  const IntegrationTile({
    super.key,
    required this.name,
    required this.icon,
    required this.status,
    this.detail,
    this.sensitive = false,
    this.kind,
    this.minPrivacy,
    this.onToggle,
    this.onAction,
    this.actionLabel,
    this.onStore,
  });

  /// Name der Integration.
  final String name;

  /// Linien-Icon.
  final WIconData icon;

  /// Zustand (aus wendelin_core).
  final IntegrationStatus status;

  /// Zusatz in der zweiten Zeile (z. B. „6 Tools“, „Login fehlt“).
  final String? detail;

  /// Zeigt das Badge „sensibel“.
  final bool sensitive;

  /// Art einer nutzerdefinierten Integration als Badge („MCP“, „HTTP“);
  /// `null` bei eingebauten.
  final String? kind;

  /// Mindest-Datenschutzstufe; im Zustand „verfügbar“ als Hinweis gezeigt.
  final PrivacyLevel? minPrivacy;

  /// Schalter (aktiv/verfügbar).
  final ValueChanged<bool>? onToggle;

  /// Aktion bei „Einrichtung nötig“ / „Fehler“.
  final VoidCallback? onAction;

  /// Beschriftung der Aktion (Standard: „Einrichten“ / „Neu anmelden“).
  final String? actionLabel;

  /// Store-Link bei `unavailable` (z. B. App nicht installiert).
  final VoidCallback? onStore;

  @override
  Widget build(BuildContext context) {
    final inactive = status == IntegrationStatus.unavailable;
    final info = Row(
      spacing: WSpace.m,
      children: [
        WIcon(icon),
        Expanded(
          // Text hat wie im Entwurf 14 Abstand oben/unten; die Zeile selbst
          // nur so viel, dass Bedienelemente mit 48 Trefferfläche passen.
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: WSpace.m14 - WSize.listRowInset,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: WSpace.xxs,
              children: [_title(), _subtitle()],
            ),
          ),
        ),
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
      child: Padding(
        // Zeilenhöhe wie im Entwurf (66), obwohl Bedienelemente eine
        // Trefferfläche von 48 haben.
        padding: const EdgeInsets.symmetric(
          horizontal: WSpace.l,
          vertical: WSize.listRowInset,
        ),
        child: Row(
          spacing: WSpace.m,
          children: [
            Expanded(
              child: inactive
                  ? Semantics(
                      container: true,
                      enabled: false,
                      child: Opacity(opacity: WOpacity.inactive, child: info),
                    )
                  : info,
            ),
            ?_trailing(),
          ],
        ),
      ),
    );
  }

  Widget _title() {
    final title = Text(name, style: WText.label);
    final badges = [?kind, if (sensitive) 'sensibel'];
    if (badges.isEmpty) return title;
    // Badges als Teil des Titels vorlesen („Kontakte, sensibel“).
    return Row(
      spacing: WSpace.s,
      children: [
        Flexible(
          child: Semantics(
            label: [name, ...badges].join(', '),
            excludeSemantics: true,
            child: title,
          ),
        ),
        for (final badge in badges) _Badge(badge),
      ],
    );
  }

  Widget _subtitle() {
    final (GlyphShape? shape, Color color, String text) = switch (status) {
      IntegrationStatus.active => (
        GlyphShape.dot,
        WColors.ok,
        detail == null ? 'Aktiv' : 'Aktiv · $detail',
      ),
      IntegrationStatus.available => (
        null,
        WColors.textMuted,
        detail ?? (minPrivacy == null ? 'Verfügbar' : 'Nur an Provider ab'),
      ),
      IntegrationStatus.setupRequired => (
        GlyphShape.triangle,
        WColors.warn,
        detail ?? 'Einrichtung nötig',
      ),
      IntegrationStatus.error => (
        GlyphShape.square,
        WColors.error,
        detail ?? 'Fehler',
      ),
      IntegrationStatus.unavailable => (
        null,
        WColors.textSecondary,
        detail ?? 'Nicht verfügbar',
      ),
    };
    final level = minPrivacy;
    final showLevel =
        status == IntegrationStatus.available &&
        detail == null &&
        level != null;
    return Text.rich(
      TextSpan(
        style: WText.caption.copyWith(color: color),
        children: [
          if (shape != null) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Glyph(shape, color: color),
            ),
            const TextSpan(text: ' '),
          ],
          TextSpan(text: text),
          if (showLevel) ...[
            const TextSpan(text: ' '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Glyph(GlyphShape.forPrivacy(level), color: color),
            ),
            TextSpan(text: ' ${level.label}'),
          ],
        ],
      ),
    );
  }

  Widget? _trailing() {
    switch (status) {
      case IntegrationStatus.active:
      case IntegrationStatus.available:
        return WSwitch(
          value: status == IntegrationStatus.active,
          onChanged: onToggle,
          semanticLabel: name,
        );
      case IntegrationStatus.setupRequired:
        return _ActionButton(
          label: actionLabel ?? 'Einrichten',
          color: WColors.warn,
          onPressed: onAction,
        );
      case IntegrationStatus.error:
        return _ActionButton(
          label: actionLabel ?? 'Neu anmelden',
          color: WColors.error,
          onPressed: onAction,
        );
      case IntegrationStatus.unavailable:
        if (onStore == null) return null;
        return TextButton(
          onPressed: onStore,
          style: TextButton.styleFrom(
            foregroundColor: WColors.link,
            textStyle: WText.buttonSmall.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: WColors.link,
            ),
            padding: EdgeInsets.zero,
            minimumSize: const Size(WSize.touchMin, WSize.touchMin),
          ),
          child: const Text('Im Store'),
        );
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(WRadius.badge),
      border: Border.all(color: WColors.lineSubtle, width: WSize.borderThin),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WSpace.xs6,
        vertical: WSpace.xxs,
      ),
      child: ExcludeSemantics(child: Text(text, style: WText.monoBadge)),
    ),
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color, width: WSize.border),
        textStyle: WText.buttonSmall,
        minimumSize: const Size(WSize.touchMin, WSize.buttonHeightSmall),
        padding: const EdgeInsets.symmetric(horizontal: WSpace.m14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WRadius.tile),
        ),
      ),
      child: Text(label),
    );
  }
}
