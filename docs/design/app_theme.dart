// Wendelin – Theme aus docs/design/tokens.json.
// Zielort im Projekt: app/lib/ui/theme/app_theme.dart
// Abhängigkeit: google_fonts (oder Fonts als Assets bündeln, siehe DESIGN.md).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  static const ok = Color(0xFF3FB97A);
  static const warn = Color(0xFFE8B341);
  static const error = Color(0xFFEF6A62);
}

abstract final class WSpace {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 20.0, xxl = 28.0;
  static const screen = 20.0;
}

abstract final class WRadius {
  static const small = 8.0, button = 12.0, buttonLarge = 14.0;
  static const card = 16.0, cardLarge = 18.0, sheet = 28.0;
}

abstract final class WText {
  static TextStyle _ui(
    double size,
    FontWeight w, {
    double? height,
    double ls = 0,
  }) => GoogleFonts.instrumentSans(
    fontSize: size,
    fontWeight: w,
    height: height,
    letterSpacing: ls * size,
    color: WColors.text,
  );

  static final transcript = _ui(26, FontWeight.w600, height: 1.2, ls: -0.01);
  static final screenTitle = _ui(26, FontWeight.w600, ls: -0.01);
  static final cardTitle = _ui(24, FontWeight.w600, height: 1.25);
  static final answer = _ui(
    18,
    FontWeight.w400,
    height: 1.45,
  ).copyWith(color: WColors.textSecondary);
  static final body = _ui(16, FontWeight.w400, height: 1.5);
  static final label = _ui(16, FontWeight.w600);
  static final button = _ui(15, FontWeight.w600);
  static final caption = _ui(
    13,
    FontWeight.w400,
  ).copyWith(color: WColors.textMuted);
  static final mono = GoogleFonts.ibmPlexMono(
    fontSize: 12,
    color: WColors.textMuted,
  );
}

enum PrivacyLevel { local, tee, eu, standard }

enum CheckStatus { ok, pending, failed }

ThemeData buildWendelinTheme() {
  const scheme = ColorScheme.dark(
    surface: WColors.ink,
    onSurface: WColors.text,
    surfaceContainer: WColors.surface,
    surfaceContainerHigh: WColors.surfaceRaised,
    primary: WColors.accent,
    onPrimary: Colors.white,
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
  );
  return base.copyWith(
    textTheme: GoogleFonts.instrumentSansTextTheme(base.textTheme)
        .apply(bodyColor: WColors.text, displayColor: WColors.text),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WColors.paper,
        foregroundColor: WColors.ink,
        minimumSize: const Size(44, 52),
        textStyle: WText.button,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WRadius.buttonLarge),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WColors.text,
        minimumSize: const Size(44, 44),
        side: const BorderSide(color: WColors.line, width: 1.5),
        textStyle: WText.button,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WRadius.button),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? Colors.white : WColors.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? WColors.accent : WColors.line,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: WColors.surface,
      hintStyle: WText.body.copyWith(color: WColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WColors.line, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WColors.accent, width: 1.5),
      ),
    ),
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
      thickness: 1,
      space: 1,
    ),
  );
}
