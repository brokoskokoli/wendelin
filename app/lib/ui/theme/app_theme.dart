// Wendelin – Theme aus docs/design/tokens.json (Quelle der Wahrheit).
//
// Übernommen aus docs/design/app_theme.dart. Abweichung: Die Schriften
// kommen als gebündelte Assets (pubspec.yaml → fonts) statt über
// google_fonts; es gibt damit keinen Code-Pfad, der Schriften aus dem Netz
// lädt. Zusätzliche Konstanten (Zwischenabstände, Komponentenmaße) stammen
// aus den Maßvorlagen in docs/design/screens/*.html und sind hier zentral
// abgelegt, damit Bausteine keine Zahlen oder Farben hart kodieren.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Schriftfamilien (in pubspec.yaml als Assets deklariert).
abstract final class WFonts {
  /// Oberflächenschrift.
  static const ui = 'InstrumentSans';

  /// Technik, Tool-Namen, IDs, Kosten, Protokoll, Chips.
  static const mono = 'IBMPlexMono';

  /// Asset-Pfade der Schriftdateien je Familie (für Tests und Lizenzen).
  static const files = <String, List<String>>{
    ui: [
      'assets/fonts/InstrumentSans-Regular.ttf',
      'assets/fonts/InstrumentSans-Medium.ttf',
      'assets/fonts/InstrumentSans-SemiBold.ttf',
      'assets/fonts/InstrumentSans-Bold.ttf',
    ],
    mono: [
      'assets/fonts/IBMPlexMono-Regular.ttf',
      'assets/fonts/IBMPlexMono-Medium.ttf',
    ],
  };

  /// OFL-Lizenztexte je Paketname im Lizenzregister.
  static const licenses = <String, String>{
    'Instrument Sans': 'assets/fonts/OFL-InstrumentSans.txt',
    'IBM Plex Mono': 'assets/fonts/OFL-IBMPlexMono.txt',
  };
}

/// Farben (tokens.json → color).
abstract final class WColors {
  static const ink = Color(0xFF101214);
  static const surface = Color(0xFF1A1D21);
  static const surfaceRaised = Color(0xFF23272C);
  static const line = Color(0xFF2E333A);
  static const lineSubtle = Color(0xFF6B7178);
  static const text = Color(0xFFEDEBE6);
  static const textSecondary = Color(0xFFC9CCD0);
  static const textMuted = Color(0xFFA3A8AE);
  static const paper = Color(0xFFF4F2ED);
  static const paperInk = Color(0xFF15171A);
  static const accent = Color(0xFF3355E8);
  static const accentLight = Color(0xFF5B7BFF);
  static const link = Color(0xFF8FA4FF);
  static const onAccent = Color(0xFFFFFFFF);

  static const ok = Color(0xFF3FB97A);
  static const warn = Color(0xFFE8B341);
  static const error = Color(0xFFEF6A62);

  /// Vollständig durchsichtig (z. B. Hintergrund von Outlined-Buttons).
  static const transparent = Color(0x00000000);
}

/// Deckkraft-Stufen.
abstract final class WOpacity {
  /// Nicht installierte Integration.
  static const inactive = 0.55;
}

/// Abstände (tokens.json → space) plus Zwischenwerte aus den Screens.
abstract final class WSpace {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 20.0, xxl = 28.0;
  static const screen = 20.0;

  /// 2: Titel ↔ Untertitel in Listenzeilen.
  static const xxs = 2.0;

  /// 3: Name ↔ Bedingung in Regelzeilen.
  static const xxs3 = 3.0;

  /// 6: Chip-Abstände, kleine Innenabstände.
  static const xs6 = 6.0;

  /// 10: Chip-Innenabstand horizontal, Logo ↔ Name.
  static const s10 = 10.0;

  /// 14: Blasen-/Karteninnenabstand, Abstand der Chatnachrichten.
  static const m14 = 14.0;

  /// 18: Abstand der Sheet-Bereiche, Innenabstand der Bestätigungskarte.
  static const l18 = 18.0;

  /// 24: Abstand unten auf Einstellungsseiten.
  static const xl24 = 24.0;

  /// 52: Abstand oben auf Screens (inkl. Statusleiste in den Vorlagen).
  static const screenTop = 52.0;
}

/// Eckenradien (tokens.json → radius) plus Zwischenwerte.
abstract final class WRadius {
  static const small = 8.0, button = 12.0, buttonLarge = 14.0;
  static const card = 16.0, cardLarge = 18.0, sheet = 28.0;

  /// Pillenform für Chips.
  static const chip = 999.0;

  /// Spitze Ecke der Nutzer-Blase.
  static const tail = 4.0;

  /// Badge „sensibel“.
  static const badge = 6.0;

  /// Icon-Kachel, kleine Outlined-Buttons.
  static const tile = 10.0;
}

/// Größen (tokens.json → size) plus Komponentenmaße.
abstract final class WSize {
  static const touchMin = 44.0;
  static const micButton = 72.0;
  static const micButtonCompact = 64.0;
  static const secondaryRound = 52.0;
  static const buttonHeight = 52.0;
  static const buttonHeightLarge = 56.0;
  static const switchWidth = 52.0;
  static const switchHeight = 32.0;

  /// Kleiner Outlined-Button in Listenzeilen (Trefferfläche bleibt ≥ 48).
  static const buttonHeightSmall = 36.0;

  /// Höhe einer Listenzeile (Integrationen) ohne Trenner.
  static const listRow = 66.0;

  /// Vertikaler Innenabstand einer Listenzeile, deren Bedienelemente eine
  /// Trefferfläche von 48 haben (ergibt [listRow]).
  static const listRowInset = (listRow - kMinInteractiveDimension) / 2;

  /// Daumen des Schalters.
  static const switchThumb = 26.0;

  /// Linien-Icon in Listen und Karten.
  static const icon = 22.0;

  /// Kleines Linien-Icon (z. B. Zurück, Beenden).
  static const iconSmall = 20.0;

  /// Icon im Mikrofon-Button (72 / 64).
  static const micIcon = 28.0;
  static const micIconCompact = 26.0;

  /// Icon-Kachel in Ergebniskarten.
  static const iconTile = 40.0;

  /// Prüfstatus-Symbol normal / im Chip.
  static const statusIcon = 20.0;
  static const statusIconSmall = 14.0;

  /// Kleines Ladezeichen (Strichstärke) in Zeilen, z. B. „Probe hören“.
  static const spinner = 20.0;
  static const spinnerStroke = 2.0;

  /// Warn-Dreieck im Kopf der Bestätigungskarte.
  static const statusIconHeader = 16.0;

  /// Kleine Symbole im Reiter „Details“ (Pfeil, Stufenwahl).
  static const iconDetail = 16.0;

  /// Form-Symbole vor Text (●, ◆, ▲, ■, ✓).
  static const glyph = 8.0;

  /// Punkt vor dem Sprachhinweis.
  static const hintDot = 8.0;

  /// Bildmarke im Sheet-Kopf.
  static const markSheet = 26.0;

  /// Bildmarke im Kopf des Hauptbildschirms.
  static const markHeader = 30.0;

  /// Schriftzug im Kopf (entspricht Schriftgröße 26).
  static const wordmarkHeader = 34.0;

  /// Standardhöhe des Lockups.
  static const lockup = 40.0;

  /// Ziehgriff des Sheets.
  static const dragHandleWidth = 40.0;
  static const dragHandleHeight = 5.0;

  /// Assistenten-Overlay: Höhe des Sheets (Vorlage 560 von 844) und
  /// größter Anteil an der Bildschirmhöhe (kleine Geräte, Tastatur).
  static const overlaySheet = 560.0;
  static const overlayMaxFraction = 0.8;

  /// Ziehgriff in Regelzeilen.
  static const ruleHandleWidth = 16.0;

  /// Wellenform: Balkenbreite, Abstand, Höhe.
  static const waveBar = 4.0;
  static const waveGap = 4.0;
  static const waveHeight = 40.0;

  /// Rahmen- und Trennlinienstärken.
  static const border = 1.5;
  static const borderThin = 1.0;
  static const divider = 1.0;

  /// Strichstärke der Linien-Icons.
  static const iconStroke = 1.8;

  /// Ring um den Mikrofon-Button beim Zuhören.
  static const micRing = 3.0;
  static const micRingGap = 3.0;

  /// Zusätzlicher Rand je Seite, wenn ein 44er Bedienelement auf die
  /// Material-Trefferfläche von 48 aufgefüllt wird. Kopfzeilen ziehen ihn
  /// vom Abstand ab, damit das Layout den Vorlagen entspricht.
  static const tapTargetInset = (kMinInteractiveDimension - touchMin) / 2;

  /// Breitenanteile: Nutzer-Blase und Antwortspalte.
  static const bubbleMaxFraction = 0.8;
  static const answerMaxFraction = 0.92;
}

/// Zeiten (tokens.json → motion).
abstract final class WMotion {
  static const undoWindow = Duration(seconds: 10);
  static const followUpListen = Duration(seconds: 5);
  static const fast = Duration(milliseconds: 150);
}

/// Textstile (tokens.json → type) plus abgeleitete Stile aus den Screens.
///
/// Stile ohne Zeilenhöhe in den Tokens bekommen trotzdem eine explizite
/// Höhe: die CSS-Zeilenhöhe „normal“ der Vorlagen, also (Ascent + Descent)
/// der Schrift × Größe, auf ganze Pixel gerundet ([normalHeight]). Ohne das
/// rundet Flutter die Zeilen größer und die Screens driften nach unten.
abstract final class WText {
  /// Ascent + Descent je Schrift (hhea, Einheiten/em) aus den TTFs.
  static const fontLineFactor = <String, double>{
    WFonts.ui: 1.22,
    WFonts.mono: 1.3,
  };

  /// Höhenfaktor für die Zeilenhöhe „normal“ von [family] bei [size].
  static double normalHeight(String family, double size) =>
      (fontLineFactor[family]! * size).roundToDouble() / size;

  static TextStyle _ui(
    double size,
    FontWeight w, {
    double? height,
    double ls = 0,
    Color color = WColors.text,
  }) => TextStyle(
    fontFamily: WFonts.ui,
    fontSize: size,
    fontWeight: w,
    height: height ?? normalHeight(WFonts.ui, size),
    letterSpacing: ls * size,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static TextStyle _mono(
    double size, {
    FontWeight w = FontWeight.w400,
    Color color = WColors.textMuted,
  }) => TextStyle(
    fontFamily: WFonts.mono,
    fontSize: size,
    fontWeight: w,
    height: normalHeight(WFonts.mono, size),
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static final transcript = _ui(26, FontWeight.w600, height: 1.2, ls: -0.01);
  static final screenTitle = _ui(26, FontWeight.w600, ls: -0.01);
  static final cardTitle = _ui(24, FontWeight.w600, height: 1.25);
  static final answer = _ui(
    18,
    FontWeight.w400,
    height: 1.45,
    color: WColors.textSecondary,
  );
  static final body = _ui(16, FontWeight.w400, height: 1.5);
  static final label = _ui(16, FontWeight.w600);
  static final button = _ui(15, FontWeight.w600);
  static final caption = _ui(13, FontWeight.w400, color: WColors.textMuted);
  static final mono = _mono(12);

  /// Antworttext im Chat (16, 1.5, sekundär).
  static final chatAnswer = body.copyWith(color: WColors.textSecondary);

  /// Nutzer-Blase (16, 1.4).
  static final bubble = _ui(16, FontWeight.w400, height: 1.4);

  /// Zitat des Gesagten im Sheet (16, gedämpft).
  static final quote = _ui(16, FontWeight.w400, color: WColors.textMuted);

  /// Zweite Zeile in Karten (14, gedämpft).
  static final detail = _ui(14, FontWeight.w400, color: WColors.textMuted);

  /// Einleitender Hinweistext auf Einstellungsseiten (14, 1.5).
  static final intro = _ui(
    14,
    FontWeight.w400,
    height: 1.5,
    color: WColors.textMuted,
  );

  /// Abschnittsüberschrift in Listen (13, 600, gedämpft).
  static final sectionLabel = _ui(
    13,
    FontWeight.w600,
    color: WColors.textMuted,
  );

  /// Überschrift eines Abschnitts auf Einstellungsseiten (18, 600, Text).
  static final sectionTitle = _ui(18, FontWeight.w600);

  /// Text in der Info-Box (14, 1.5, sekundär).
  static final info = _ui(
    14,
    FontWeight.w400,
    height: 1.5,
    color: WColors.textSecondary,
  );

  /// Titel eines Eintrags in der Bestätigungskarte (17, 600).
  static final itemTitle = _ui(17, FontWeight.w600);

  /// Große Buttons (17, 600).
  static final buttonLarge = _ui(17, FontWeight.w600);

  /// Kleine Buttons und Links in Listenzeilen (14, 600).
  static final buttonSmall = _ui(14, FontWeight.w600);

  /// Badge „sensibel“ (Mono 11, 500).
  static final monoBadge = _mono(
    11,
    w: FontWeight.w500,
    color: WColors.textSecondary,
  );

  /// Kopfzeile der Bestätigungskarte (Mono 12, Versalien, Laufweite 0.04).
  static final monoCaps = mono.copyWith(
    color: WColors.warn,
    letterSpacing: 0.04 * 12,
  );
}

/// Registriert die OFL-Lizenztexte der gebündelten Schriften.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in WFonts.licenses.entries) {
      final text = await rootBundle.loadString(entry.value);
      yield LicenseEntryWithLineBreaks([entry.key], text);
    }
  });
}

/// Dunkles Standard-Theme.
ThemeData buildWendelinTheme() {
  const scheme = ColorScheme.dark(
    surface: WColors.ink,
    onSurface: WColors.text,
    surfaceContainer: WColors.surface,
    surfaceContainerHigh: WColors.surfaceRaised,
    primary: WColors.accent,
    onPrimary: WColors.onAccent,
    secondary: WColors.paper,
    onSecondary: WColors.ink,
    outline: WColors.line,
    outlineVariant: WColors.lineSubtle,
    error: WColors.error,
    onError: WColors.ink,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: WColors.ink,
    fontFamily: WFonts.ui,
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: WFonts.ui,
      bodyColor: WColors.text,
      displayColor: WColors.text,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WColors.paper,
        foregroundColor: WColors.ink,
        minimumSize: const Size(WSize.touchMin, WSize.buttonHeight),
        textStyle: WText.button,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WRadius.buttonLarge),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WColors.text,
        minimumSize: const Size(WSize.touchMin, WSize.touchMin),
        side: const BorderSide(color: WColors.line, width: WSize.border),
        textStyle: WText.button,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WRadius.button),
        ),
      ),
    ),
    switchTheme: _switchTheme(),
    inputDecorationTheme: _inputTheme(),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: WColors.ink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(WRadius.sheet),
        ),
      ),
      showDragHandle: true,
      dragHandleColor: WColors.line,
    ),
    dividerTheme: const DividerThemeData(
      color: WColors.surfaceRaised,
      thickness: WSize.divider,
      space: WSize.divider,
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: WText.caption.copyWith(color: WColors.paperInk),
      decoration: BoxDecoration(
        color: WColors.paper,
        borderRadius: BorderRadius.circular(WRadius.small),
      ),
    ),
  );
}

SwitchThemeData _switchTheme() => SwitchThemeData(
  thumbColor: WidgetStateProperty.resolveWith(
    (s) =>
        s.contains(WidgetState.selected) ? WColors.onAccent : WColors.textMuted,
  ),
  trackColor: WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.selected) ? WColors.accent : WColors.line,
  ),
  trackOutlineColor: const WidgetStatePropertyAll(WColors.transparent),
);

InputDecorationTheme _inputTheme() => InputDecorationTheme(
  filled: true,
  fillColor: WColors.surface,
  hintStyle: WText.body.copyWith(color: WColors.textMuted),
  contentPadding: const EdgeInsets.symmetric(
    horizontal: WSpace.l,
    vertical: WSpace.m14,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(WRadius.card),
    borderSide: const BorderSide(color: WColors.line, width: WSize.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(WRadius.card),
    borderSide: const BorderSide(color: WColors.accent, width: WSize.border),
  ),
);

/// Nur für Tests sichtbar: alle Farbtokens nach Namen (für den Tokens-Test).
@visibleForTesting
const wColorTokens = <String, Color>{
  'ink': WColors.ink,
  'surface': WColors.surface,
  'surfaceRaised': WColors.surfaceRaised,
  'line': WColors.line,
  'lineSubtle': WColors.lineSubtle,
  'text': WColors.text,
  'textSecondary': WColors.textSecondary,
  'textMuted': WColors.textMuted,
  'paper': WColors.paper,
  'paperInk': WColors.paperInk,
  'accent': WColors.accent,
  'accentLight': WColors.accentLight,
  'link': WColors.link,
  'onAccent': WColors.onAccent,
  'status.ok': WColors.ok,
  'status.warn': WColors.warn,
  'status.error': WColors.error,
};
