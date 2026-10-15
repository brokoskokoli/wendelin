import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

/// Linien-Icon (viewBox 24, Strich 1.8, abgerundet) als SVG-Daten.
///
/// Die Pfade stammen aus den Maßvorlagen in docs/design/screens/*.html.
/// Schwarz gezeichnet und beim Rendern per Farbfilter eingefärbt.
@immutable
class WIconData {
  const WIconData._(this.body, {this.viewBox = '0 0 24 24'});

  /// SVG-Inhalt ohne `<svg>`-Hülle.
  final String body;

  /// SVG-viewBox.
  final String viewBox;

  /// Vollständiges SVG-Dokument.
  String get svg =>
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="$viewBox">$body</svg>';
}

const _s =
    'fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round"';
const _sj = '$_s stroke-linejoin="round"';

/// Icon-Satz der App.
abstract final class WIcons {
  /// Einstellungen (Schieberegler).
  static const settings = WIconData._(
    '<path d="M4 7 L14 7 M18 7 L20 7 M4 17 L6 17 M10 17 L20 17" $_s/>'
    '<circle cx="16" cy="7" r="2.2" $_s/><circle cx="8" cy="17" r="2.2" $_s/>',
  );

  /// Zurück.
  static const back = WIconData._(
    '<path d="M15 5 L8 12 L15 19" fill="none" stroke="#000" stroke-width="2" '
    'stroke-linecap="round" stroke-linejoin="round"/>',
  );

  /// Tastatur (Texteingabe).
  static const keyboard = WIconData._(
    '<rect x="2.5" y="6" width="19" height="12" rx="2.5" $_s/>'
    '<path d="M6 10 L6.2 10 M10 10 L10.2 10 M14 10 L14.2 10 M18 10 L18.2 10 '
    'M8 14 L16 14" $_s/>',
  );

  /// Schließen / Beenden.
  static const close = WIconData._(
    '<path d="M6 6 L18 18 M18 6 L6 18" fill="none" stroke="#000" '
    'stroke-width="2" stroke-linecap="round"/>',
  );

  /// Mikrofon.
  static const mic = WIconData._(
    '<rect x="9" y="3" width="6" height="12" rx="3" fill="none" stroke="#000" '
    'stroke-width="2"/><path d="M5.5 11.5 a6.5 6.5 0 0 0 13 0 M12 18 L12 21" '
    'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round"/>',
  );

  /// Neues Gespräch (Sprechblase mit Plus).
  static const newChat = WIconData._(
    '<path d="M20 12.5 V16 a2.5 2.5 0 0 1 -2.5 2.5 H10 L6 21 V18.5 H6.5 '
    'A2.5 2.5 0 0 1 4 16 V8 a2.5 2.5 0 0 1 2.5 -2.5 H12" $_sj/>'
    '<path d="M18 3 L18 9 M15 6 L21 6" $_s/>',
  );

  /// Senden (Pfeil nach oben).
  static const send = WIconData._(
    '<path d="M12 19 L12 5 M6 11 L12 5 L18 11" $_sj/>',
  );

  /// Kalender.
  static const calendar = WIconData._(
    '<rect x="3.5" y="5" width="17" height="15" rx="2.5" $_s/>'
    '<path d="M3.5 10 L20.5 10 M8 3 L8 7 M16 3 L16 7" $_s/>',
  );

  /// Notiz / Dokument.
  static const note = WIconData._(
    '<path d="M6 3.5 L15 3.5 L19 7.5 L19 20.5 L6 20.5 Z" $_sj/>'
    '<path d="M9 11 L16 11 M9 15 L14 15" $_s/>',
  );

  /// Einkaufswagen.
  static const cart = WIconData._(
    '<path d="M4 7 L6 7 L8 17 L18 17 L20 9 L7 9" $_sj/>'
    '<circle cx="9" cy="20" r="1.3" fill="#000"/>'
    '<circle cx="17" cy="20" r="1.3" fill="#000"/>',
  );

  /// Musik / Streaming.
  static const music = WIconData._(
    '<circle cx="12" cy="12" r="8.5" $_s/>'
    '<path d="M8 10 C11 9, 14 9.5, 16.5 11 M8.5 13.5 C11 12.8, 13.5 13.2, '
    '15.5 14.3" fill="none" stroke="#000" stroke-width="1.6" '
    'stroke-linecap="round"/>',
  );

  /// Wellen (Wetter und Meer).
  static const waves = WIconData._(
    '<path d="M3 15 C6 12, 9 12, 12 15 C15 18, 18 18, 21 15 M3 10 C6 7, 9 7, '
    '12 10 C15 13, 18 13, 21 10" $_s/>',
  );

  /// Person (Kontakte).
  static const person = WIconData._(
    '<circle cx="12" cy="9" r="3.5" $_s/>'
    '<path d="M5 20 C6 15.5, 18 15.5, 19 20" $_s/>',
  );

  /// Aufgabe (Kästchen mit Haken).
  static const task = WIconData._(
    '<rect x="4" y="4" width="16" height="16" rx="3" $_s/>'
    '<path d="M8 12 L11 15 L16 9" $_sj/>',
  );

  /// Zwischenablage (Klemmbrett).
  static const clipboard = WIconData._(
    '<rect x="5" y="4.5" width="14" height="16" rx="2.5" $_s/>'
    '<path d="M9 3 L15 3 L15 6 L9 6 Z M8.5 11 L15.5 11 M8.5 15 L13.5 15" $_sj/>',
  );

  /// Taschenlampe.
  static const flashlight = WIconData._(
    '<path d="M8 3 L16 3 L16 7 L14 9 L14 20 L10 20 L10 9 L8 7 Z" $_sj/>'
    '<path d="M12 12 L12 14" $_sj/>',
  );

  /// Globus (Web).
  static const globe = WIconData._(
    '<circle cx="12" cy="12" r="8.5" $_s/>'
    '<path d="M3.5 12 L20.5 12 M12 3.5 C9 7, 9 17, 12 20.5 '
    'M12 3.5 C15 7, 15 17, 12 20.5" $_s/>',
  );

  /// Wecker (Uhr mit Glocken).
  static const alarm = WIconData._(
    '<circle cx="12" cy="13" r="7" $_s/>'
    '<path d="M12 9.5 L12 13 L14.5 15 M5 5.5 L7.5 3.5 M19 5.5 L16.5 3.5" '
    '$_sj/>',
  );

  /// Abspielen (Dreieck).
  static const play = WIconData._('<path d="M8 5.5 L18 12 L8 18.5 Z" $_sj/>');

  /// Stopp (Quadrat).
  static const stop = WIconData._(
    '<rect x="6.5" y="6.5" width="11" height="11" rx="2" $_sj/>',
  );

  /// Ziehgriff (sechs Punkte), viewBox 16 × 22.
  static const dragHandle = WIconData._(
    '<circle cx="5" cy="5" r="1.6"/><circle cx="11" cy="5" r="1.6"/>'
    '<circle cx="5" cy="11" r="1.6"/><circle cx="11" cy="11" r="1.6"/>'
    '<circle cx="5" cy="17" r="1.6"/><circle cx="11" cy="17" r="1.6"/>',
    viewBox: '0 0 16 22',
  );

  /// Fester Platz (senkrechter Strich), viewBox 16 × 22.
  static const fixedHandle = WIconData._(
    '<path d="M8 4 L8 18" fill="none" stroke="#000" stroke-width="1.6" '
    'stroke-linecap="round"/>',
    viewBox: '0 0 16 22',
  );
}

/// Zeichnet ein [WIconData]; dekorativ (Bedeutung trägt der Aufrufer).
class WIcon extends StatelessWidget {
  /// Erstellt ein Icon.
  const WIcon(
    this.icon, {
    super.key,
    this.size = WSize.icon,
    this.height,
    this.color = WColors.text,
  });

  /// Icon-Daten.
  final WIconData icon;

  /// Breite (und Höhe, falls [height] fehlt).
  final double size;

  /// Abweichende Höhe für nicht quadratische Icons.
  final double? height;

  /// Farbe.
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.string(
      icon.svg,
      width: size,
      height: height ?? size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
  );
}

/// Form eines [WIconButton].
enum WIconButtonShape {
  /// Quadratische Kachel auf `surface` (Kopfzeilen).
  tile,

  /// Runder Sekundär-Button mit Rahmen (Steuerleiste).
  round,
}

/// Icon-Button mit Tooltip/Semantics und Trefferfläche ≥ 48.
class WIconButton extends StatelessWidget {
  /// Erstellt einen Icon-Button.
  const WIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.shape = WIconButtonShape.tile,
    this.iconSize = WSize.icon,
  });

  /// Icon.
  final WIconData icon;

  /// Tooltip und Semantics-Label.
  final String tooltip;

  /// Aktion; `null` deaktiviert den Button.
  final VoidCallback? onPressed;

  /// Form.
  final WIconButtonShape shape;

  /// Icon-Größe.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final tile = shape == WIconButtonShape.tile;
    final extent = tile ? WSize.touchMin : WSize.secondaryRound;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: WIcon(
        icon,
        size: iconSize,
        color: onPressed == null ? WColors.textMuted : WColors.text,
      ),
      style: IconButton.styleFrom(
        fixedSize: Size.square(extent),
        minimumSize: Size.square(extent),
        padding: EdgeInsets.zero,
        backgroundColor: tile ? WColors.surface : WColors.transparent,
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: tile
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WRadius.button),
              )
            : const CircleBorder(
                side: BorderSide(color: WColors.line, width: WSize.border),
              ),
      ),
    );
  }
}
