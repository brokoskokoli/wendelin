# WP07 – Design-System (`app/lib/ui/design/`)

Flutter. Abhängig von: nichts außer Flutter, `flutter_svg`, `google_fonts` (Runtime-Fetch aus!). Grundlage: `docs/design/DESIGN.md`, `tokens.json`, `app_theme.dart`, `screens/*.html` (Maße) und `screens/*@1x.png` (Sichtabgleich).

## Inhalt
- `app/lib/ui/theme/app_theme.dart` aus `docs/design/app_theme.dart` übernehmen; Fonts (Instrument Sans 400/500/600/700, IBM Plex Mono 400/500) als TTF-Assets in `app/assets/fonts/` bündeln (OFL-Lizenztext mit ablegen), `GoogleFonts.config.allowRuntimeFetching = false`. Tokens-Test: Werte in `WColors`/`WSpace`/`WRadius` stimmen mit `docs/design/tokens.json` überein (Test liest die JSON).
- Logos aus `docs/design/logo/` als Assets (`app/assets/logo/`), `WendelinWordmark`, `WendelinMark`, `WendelinLockup` per `flutter_svg`.
- Bausteine (je eigene Datei, nur Darstellung, keine Geschäftslogik, Daten per Parameter):
  `MicButton` (72/64, Zustände idle/listening/thinking/disabled, Semantics), `Waveform` (Amplituden-Liste), `ProviderChip(name, PrivacyLevel, CheckStatus?)`, `PrivacyChip`, `CheckStatusIcon(CheckStatus)` (Kreis+Haken / Dreieck / Quadrat+Kreuz), `ToolResultCard(title, detail, toolName, onUndo, undoRemaining)`, `ConfirmationCard(title, detail, toolName, risk, onYes, onNo)`, `ToolChip`, `UserBubble`, `AssistantText`, `EscalationDivider`, `IntegrationTile` (5 Zustände + Badge „sensibel“), `RuleTile`, `SectionCard`.
- `app/lib/ui/design/gallery.dart`: Galerie-Screen mit allen Bausteinen (Debug-Route).
- Golden-Tests für jeden Baustein in allen Zuständen (Fonts in Tests laden!) und für drei Kompositionen, die die Screens `hauptbildschirm`, `bestaetigung`, `integrationen` mit Beispieldaten nachstellen (390×844).

## Abnahmekriterien
- [ ] Goldens visuell vom Reviewer gegen die PNGs geprüft (Farben, Abstände, Formen, Texte).
- [ ] Alle Icon-Buttons mit Semantics/Tooltip; Touch-Ziele ≥ 44 (Test mit `meetsGuideline(androidTapTargetGuideline)` und `textContrastGuideline`).
- [ ] Keine hartkodierten Farben/Abstände außerhalb des Themes (grep-Test).
- [ ] `flutter analyze` und `flutter test` grün.
