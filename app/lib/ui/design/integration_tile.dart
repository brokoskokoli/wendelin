import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../theme/app_theme.dart';
import 'glyphs.dart';
import 'icons.dart';
import 'privacy_chip.dart';
import 'w_switch.dart';

/// Zustand einer Integration (Konzept: Tool-System → Zustand).
enum IntegrationState {
  /// Eingeschaltet und bereit: Schalter an, grüner Status.
  active,

  /// Eingerichtet, aber aus: Schalter aus.
  available,

  /// Einrichtung nötig (z. B. Login fehlt): gelber Button.
  setupRequired,

  /// Fehler (z. B. Token abgelaufen): roter Button.
  error,

  /// Zugehörige App nicht installiert: gedämpft, Store-Link.
  notInstalled,
}

/// Zeile einer Integration in der Liste (innerhalb einer [SectionCard]).
class IntegrationTile extends StatelessWidget {
  /// Erstellt eine Integrationszeile.
  const IntegrationTile({
    super.key,
    required this.name,
    required this.icon,
    required this.state,
    this.detail,
    this.sensitive = false,
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

  /// Zustand.
  final IntegrationState state;

  /// Zusatz in der zweiten Zeile (z. B. „6 Tools“, „Login fehlt“).
  final String? detail;

  /// Zeigt das Badge „sensibel“.
  final bool sensitive;

  /// Mindest-Datenschutzstufe; im Zustand „verfügbar“ als Hinweis gezeigt.
  final PrivacyLevel? minPrivacy;

  /// Schalter (aktiv/verfügbar).
  final ValueChanged<bool>? onToggle;

  /// Aktion bei „Einrichtung nötig“ / „Fehler“.
  final VoidCallback? onAction;

  /// Beschriftung der Aktion (Standard: „Einrichten“ / „Neu anmelden“).
  final String? actionLabel;

  /// Store-Link bei „nicht installiert“.
  final VoidCallback? onStore;

  @override
  Widget build(BuildContext context) {
    final inactive = state == IntegrationState.notInstalled;
    final info = Row(
      spacing: WSpace.m,
      children: [
        WIcon(icon),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WSpace.xxs,
            children: [_title(), _subtitle()],
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
    if (!sensitive) return title;
    // Badge als Teil des Titels vorlesen („Kontakte, sensibel“).
    return Row(
      spacing: WSpace.s,
      children: [
        Flexible(
          child: Semantics(
            label: '$name, sensibel',
            excludeSemantics: true,
            child: title,
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(WRadius.badge),
            border: Border.all(
              color: WColors.lineSubtle,
              width: WSize.borderThin,
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: WSpace.xs6,
              vertical: WSpace.xxs,
            ),
            child: ExcludeSemantics(
              child: Text('sensibel', style: WText.monoBadge),
            ),
          ),
        ),
      ],
    );
  }

  Widget _subtitle() {
    final (GlyphShape? shape, Color color, String text) = switch (state) {
      IntegrationState.active => (
        GlyphShape.dot,
        WColors.ok,
        detail == null ? 'Aktiv' : 'Aktiv · $detail',
      ),
      IntegrationState.available => (
        null,
        WColors.textMuted,
        detail ?? (minPrivacy == null ? 'Verfügbar' : 'Nur an Provider ab'),
      ),
      IntegrationState.setupRequired => (
        GlyphShape.triangle,
        WColors.warn,
        detail ?? 'Einrichtung nötig',
      ),
      IntegrationState.error => (
        GlyphShape.square,
        WColors.error,
        detail ?? 'Fehler',
      ),
      IntegrationState.notInstalled => (
        null,
        WColors.textSecondary,
        detail ?? 'App nicht installiert',
      ),
    };
    final level = minPrivacy;
    final showLevel =
        state == IntegrationState.available && detail == null && level != null;
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
    switch (state) {
      case IntegrationState.active:
      case IntegrationState.available:
        return WSwitch(
          value: state == IntegrationState.active,
          onChanged: onToggle,
          semanticLabel: name,
        );
      case IntegrationState.setupRequired:
        return _ActionButton(
          label: actionLabel ?? 'Einrichten',
          color: WColors.warn,
          onPressed: onAction,
        );
      case IntegrationState.error:
        return _ActionButton(
          label: actionLabel ?? 'Neu anmelden',
          color: WColors.error,
          onPressed: onAction,
        );
      case IntegrationState.notInstalled:
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
