# Wendelin – Design-Übergabe

Stand 12.10.2026. Ergänzt `../../Voice Agent App – Gesamtkonzept.md` (Abschnitt „UI/UX und Einstellungen“).

## Inhalt

| Pfad | Inhalt |
| --- | --- |
| `tokens.json` | Farben, Schrift, Abstände, Radien, Größen – Quelle der Wahrheit |
| `app_theme.dart` | `ThemeData` + Konstanten (`WColors`, `WText`, `WSpace`, `WRadius`) aus den Tokens |
| `screens/*.html` | Screens als statisches HTML/CSS (390 × 844), exakte Maße und Texte |
| `screens/*@1x.png`, `*@2x.png` | Referenzbilder der Screens |
| `logo/` | Bildmarke, Schriftzug (als Pfade), Lockups, App-Icons (SVG + PNG 1024), Benachrichtigungs-Icon |
| `reference/` | Logo-Set und Farb-/Bausteintafel als HTML und PNG |

**Arbeitsweise für den Coder:** Die HTML-Dateien sind die Maßvorlage (Abstände, Größen, Texte stehen als Inline-Styles drin), die PNGs der Sichtabgleich. Werte nicht aus dem HTML abtippen, sondern über `WColors`/`WText`/`WSpace` aus `app_theme.dart` nehmen. Weicht HTML von `tokens.json` ab, gilt `tokens.json`.

## Grundregeln

- Dunkles Theme ist Standard. Hintergrund `ink`, Karten `surface`, Rahmen `line`.
- Ein Akzent: Kobalt (`accent`) nur für Mikrofon-Button, aktive Schalter, Auswahl. Keine Verläufe, keine Glow-Effekte.
- Status immer **Farbe + Form**: geprüft = Kreis mit Haken (grün), ausstehend/Bestätigung = Dreieck (gelb), Fehler = Quadrat mit Kreuz (rot), nicht bestätigt (Quittung nicht abrufbar, K44) = grauer Ring mit Strich.
- Datenschutzstufe als Chip, unterschieden über Füllung/Rahmen (siehe `tokens.json → privacyLevel`): ● lokal, ◆ TEE, ▲ EU, ○ Standard.
- Technisches (Tool-Namen, IDs, Kosten) in IBM Plex Mono 12, `textMuted`.
- Touch-Ziele ≥ 44, Primär-Buttons 52–56 hoch. Alle Icon-Buttons mit `Semantics`/`tooltip`.
- Icons: Linien-Icons, 1.8 Strichstärke, abgerundet. Passend: `lucide_icons` oder Material Symbols Rounded (outlined).

## Screens → Widgets

| Screen | Datei | Konzept-Bezug | Widget-Struktur (Vorschlag) |
| --- | --- | --- | --- |
| Assistenten-Overlay | `overlay` | Oberflächen → Assistenten-Overlay | Modal Bottom Sheet (Höhe ~560) über `VoiceInteractionSession`-Fenster: Kopf (Marke + `ProviderChip` mit `CheckStatusIcon`), `TranscriptText`, `ToolResultCard` (Rückgängig mit Countdown 10 s), Antworttext, Steuerleiste (Tastatur · `Waveform` + `MicButton` · Beenden), Hinweis Gesprächsmodus |
| Bestätigung | `bestaetigung` | Risikostufen → `external` | gleiches Sheet; `ConfirmationCard` (gelber Rahmen, Dreieck, Tool-Name + Stufe), zwei Buttons (Outlined „Nein“, Filled „Ja“), Sprachhinweis „ja/nein“ |
| Hauptbildschirm | `hauptbildschirm` | Oberflächen → Hauptbildschirm | `Scaffold`: Kopf (Lockup + Einstellungen), Chips (Provider, Kosten heute), `ListView` mit `UserBubble`, `ToolChip`, `AssistantText`, `EscalationDivider`; unten `TextField` + `MicButton` (64) |
| Integrationen | `integrationen` | Tool-System → Zustand einer Integration | Liste in `surface`-Karte; `IntegrationTile` mit 5 Zuständen: aktiv (Switch an, grüner Status), verfügbar (Switch aus), Einrichtung nötig (gelber Outlined-Button), Fehler (roter Outlined-Button), nicht installiert (Opazität 0.55 + Store-Link); Badge „sensibel“; unten „+ MCP-Server“, „+ HTTP-Tool“ |
| Routing | `routing` | Routing und Eskalation → Regel-Editor | Testfeld + Ergebnis-Chip; `ReorderableListView` mit `RuleTile` (Ziehgriff, Name, Bedingung in Mono); aktive Regel mit Kobalt-Rahmen; Default-Regel gestrichelt, nicht verschiebbar (keine Eskalationskette mehr, K28); Filled-Button „+ Regel“ |
| TEE-Prüfprotokoll | `pruefprotokoll` | TEE → Prüfprotokoll (UI) | Sitzungskarte (Provider, Keyset-Digest, Keyset, Frische, 4 Prüfschritte), Quittungsliste mit `CheckStatusIcon`, JSON-Export, Filled-Button „Neu attestieren“ |

Wiederverwendbare Bausteine: `MicButton`, `ProviderChip(PrivacyLevel)`, `CheckStatusIcon(CheckStatus)`, `ToolResultCard`, `ConfirmationCard`, `ToolChip`, `IntegrationTile`, `RuleTile`, `Waveform`, `WendelinWordmark`.

Die grauen Blöcke hinter Overlay und Bestätigung stehen nur für „irgendeine andere App“ und werden nicht nachgebaut.

## Einstellungsseiten: Überschrift, Info, Link

Drei Bausteine, nie seitenweise nachgebaut (`app/lib/ui/design/`, `app/lib/ui/settings/settings_page.dart`):

- **Überschrift:** `WText.sectionTitle` (18/600, `text`, etwas Abstand darüber) in `SettingsSection` und im Titel von `SectionCard`. Größer als Einträge (`WText.label` 16), `sectionLabel` (13, gedämpft) bleibt nur für kleine Beschriftungen.
- **Info:** `InfoBox`: Fläche `surfaceRaised`, Radius 16, Innenabstand 12, ⓘ-Icon links, Text `WText.info` (14, `textSecondary`). `SettingsPage.intro` und freistehende Erläuterungen nutzen sie; Fehler- und Statuszeilen bleiben `caption`.
- **Link/Aktion nach außen:** `LinkButton`: Outlined, linksbündig, ≥ 44 hoch, seitlicher Innenabstand `WSpace.l` (Text fluchtet mit dem Zeilentext der Karte darüber), Text in `link`, ↗ dahinter (Sprung aus der App: Systemeinstellungen, Webseite). `external: false` ohne ↗ für Wechsel innerhalb der App.

## Logo

- **Bildmarke** = Ohrmuschel-Spirale mit Punkt. Hell auf dunkel: Spirale `text`, Punkt `accentLight`. Dunkel auf hell: Spirale `paperInk`, Punkt `accent`.
- **Schriftzug** = „wendelin“ in Instrument Sans 600, Laufweite −3 %. Das **i** ist eigens gebaut: Stamm reicht unter die Grundlinie, der i-Punkt ist eine kleine Ohrmuschel in umgekehrten Farben (Spirale blau, Punkt + Stamm wie die Schrift). Abstand i–n enger als normal.
- Den Schriftzug **nicht** als Text setzen, sondern `logo/wendelin-wordmark*.svg` per `flutter_svg` einbinden (Buchstaben sind als Pfade enthalten, keine Font-Abhängigkeit).
- Mindestgrößen: Bildmarke 24 px (darunter `wendelin-notification.svg`), Schriftzug 26 px Höhe.

| Datei | Zweck |
| --- | --- |
| `wendelin-mark.svg` / `-on-dark` / `-white` | Bildmarke für hell / dunkel / Kobalt |
| `wendelin-wordmark.svg` / `-on-dark` / `-white` | Schriftzug |
| `wendelin-lockup.svg` / `-on-dark` | Bildmarke + Schriftzug nebeneinander |
| `wendelin-notification.svg` | Android-Statusleiste: weiß auf transparent, vereinfachte Spirale → als Vector Drawable `ic_stat_wendelin` |
| `app-icon-dark.png` (Standard), `-cobalt`, `-light` | App-Icon 1024, randlos (OS maskiert) |
| `app-icon-foreground.png` | Android Adaptive Icon Vordergrund (Hintergrund `#101214`) |

`flutter_launcher_icons` (pubspec):

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "docs/design/logo/app-icon-dark.png"
  adaptive_icon_background: "#101214"
  adaptive_icon_foreground: "docs/design/logo/app-icon-foreground.png"
  remove_alpha_ios: true
```

## Schriften

Instrument Sans und IBM Plex Mono stehen unter der SIL Open Font License. Für Datenschutz („kein Netz bis zum Wake Word“) die Fonts **als Assets bündeln** statt zur Laufzeit von Google zu laden: TTFs in `app/assets/fonts/`, in `pubspec.yaml` deklarieren und `GoogleFonts.config.allowRuntimeFetching = false` setzen.

## Offen

- Helles Theme ist nur in den Tokens angelegt (`paper`, `paperInk`), Screens gibt es nur dunkel.
- Onboarding, Provider-Einrichtung, Einstellungsübersicht, Gedächtnis, Kosten: ohne Entwurf in `screens/`, in der App umgesetzt.
- Markenrecherche „Wendelin“ (DPMA/EUIPO/USPTO, Klassen 9/42) und Bildähnlichkeitsprüfung des Logos. Der Stand ist hier nicht festgehalten (v0.1.0 ist bereits veröffentlicht); Maintainer entscheidet, ob erledigt oder bewusst offen.
